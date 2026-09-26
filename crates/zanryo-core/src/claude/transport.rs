use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use portable_pty::{CommandBuilder, PtySize, native_pty_system};

use super::screen::UsageScreen;
use crate::{RateLimit, Result, ZanryoError};

#[derive(Clone, Debug)]
pub struct ProbeConfig {
    pub executable: PathBuf,
    /// Must already be trusted in Claude. The probe never approves prompts.
    pub working_directory: PathBuf,
    pub timeout: Duration,
}

impl ProbeConfig {
    pub fn new(executable: PathBuf, working_directory: PathBuf) -> Self {
        Self {
            executable,
            working_directory,
            timeout: Duration::from_secs(20),
        }
    }
}

/// A bounded, read-only subscription probe. This does not touch SQLite or
/// perform a model request. The app must opt in before scheduling this probe.
pub struct ClaudeUsageProbe {
    config: ProbeConfig,
    serial: Mutex<()>,
}

impl ClaudeUsageProbe {
    pub fn new(config: ProbeConfig) -> Self {
        Self {
            config,
            serial: Mutex::new(()),
        }
    }

    pub fn read(&self) -> Result<Vec<RateLimit>> {
        // Reject overlapping probes rather than spawning extra CLI sessions.
        let _guard = self
            .serial
            .try_lock()
            .map_err(|_| unavailable("probe already running"))?;
        if !self.config.executable.is_absolute()
            || !self.config.working_directory.is_absolute()
            || self.config.timeout.is_zero()
            || self.config.timeout > Duration::from_secs(30)
        {
            return Err(unavailable("invalid probe configuration"));
        }
        probe(&self.config)
    }
}

fn unavailable(reason: &str) -> ZanryoError {
    ZanryoError::Transport(format!("Claude usage unavailable: {reason}"))
}

fn command(config: &ProbeConfig) -> CommandBuilder {
    let mut cmd = CommandBuilder::new(&config.executable);
    cmd.args([
        "--safe-mode",
        "--ax-screen-reader",
        "--strict-mcp-config",
        "--mcp-config",
        "{\"mcpServers\":{}}",
        "--tools",
        "",
    ]);
    cmd.cwd(&config.working_directory);
    cmd.env("TERM", "xterm-256color");
    cmd.env("LANG", "en_US.UTF-8");
    cmd.env("LC_ALL", "en_US.UTF-8");
    // Subscription only. Do not substitute a paid API/gateway source or inherit
    // nested-agent markers. Native login remains the CLI's responsibility.
    for key in [
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_BASE_URL",
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_FOUNDRY",
        "CLAUDECODE",
    ] {
        cmd.env_remove(key);
    }
    cmd
}

struct ChildGuard(Box<dyn portable_pty::Child + Send + Sync>);
impl Drop for ChildGuard {
    fn drop(&mut self) {
        if !matches!(self.0.try_wait(), Ok(Some(_))) {
            let _ = self.0.kill();
        }
        let _ = self.0.wait();
    }
}

fn probe(config: &ProbeConfig) -> Result<Vec<RateLimit>> {
    let pty = native_pty_system()
        .openpty(PtySize {
            rows: 80,
            cols: 160,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|_| unavailable("cannot create terminal"))?;
    nonblocking(pty.master.as_ref())?;
    let mut reader = pty
        .master
        .try_clone_reader()
        .map_err(|_| unavailable("cannot read terminal"))?;
    let mut writer = pty
        .master
        .take_writer()
        .map_err(|_| unavailable("cannot write terminal"))?;
    let mut child = ChildGuard(
        pty.slave
            .spawn_command(command(config))
            .map_err(|_| unavailable("cannot start CLI"))?,
    );
    drop(pty.slave);
    let result = drive(&mut reader, &mut writer, &mut child, config.timeout);
    drop(reader);
    drop(writer);
    drop(child);
    drop(pty.master);
    result
}

#[cfg(unix)]
fn nonblocking(master: &dyn portable_pty::MasterPty) -> Result<()> {
    use nix::fcntl::{FcntlArg, OFlag, fcntl};
    let fd = master
        .as_raw_fd()
        .ok_or_else(|| unavailable("terminal has no descriptor"))?;
    let flags =
        fcntl(fd, FcntlArg::F_GETFL).map_err(|_| unavailable("cannot read terminal flags"))?;
    fcntl(
        fd,
        FcntlArg::F_SETFL(OFlag::from_bits_truncate(flags) | OFlag::O_NONBLOCK),
    )
    .map_err(|_| unavailable("cannot bound terminal reads"))?;
    Ok(())
}

#[cfg(not(unix))]
fn nonblocking(_: &dyn portable_pty::MasterPty) -> Result<()> {
    Err(unavailable(
        "bounded terminal reads are not supported on this platform",
    ))
}

fn drive(
    reader: &mut Box<dyn Read + Send>,
    writer: &mut Box<dyn Write + Send>,
    child: &mut ChildGuard,
    timeout: Duration,
) -> Result<Vec<RateLimit>> {
    let started = Instant::now();
    let mut last_output = Instant::now();
    let mut screen = UsageScreen::new();
    let mut requested = false;
    let mut answer = None;
    let mut leaving_dialog = false;
    let mut exiting = false;
    let mut buffer = [0_u8; 8192];
    loop {
        if started.elapsed() >= timeout {
            return Err(unavailable(if !requested {
                "CLI did not reach the supported safe prompt"
            } else if exiting {
                "CLI did not finish exiting"
            } else if leaving_dialog {
                "CLI did not close the usage dialog"
            } else {
                "timed out without a complete fresh response"
            }));
        }
        match reader.read(&mut buffer) {
            Ok(size) if size > 0 => {
                screen.feed(&buffer[..size])?;
                last_output = Instant::now();
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
            Ok(_) | Err(_) => {
                return if exiting {
                    answer.ok_or_else(|| unavailable("no response"))
                } else {
                    Err(unavailable("CLI closed before completion"))
                };
            }
        }
        if screen.blocked() {
            return Err(unavailable(
                "authentication, approval or refresh error; open Claude manually",
            ));
        }
        if child
            .0
            .try_wait()
            .map_err(|_| unavailable("cannot check CLI"))?
            .is_some()
        {
            return if exiting {
                answer.ok_or_else(|| unavailable("no response"))
            } else {
                Err(unavailable("CLI exited before completion"))
            };
        }
        // Silence boundary prevents accepting a partially painted frame or
        // sending a command while a prompt is still being replaced.
        if last_output.elapsed() < Duration::from_millis(300) {
            continue;
        }
        if !requested && screen.ready() {
            screen.mark_requested();
            write_command(writer, b"/usage\r")?;
            requested = true;
        } else if requested && !leaving_dialog {
            if let Ok(limits) = screen.completed(chrono::Utc::now()) {
                answer = Some(limits);
                write_command(writer, b"\x1b")?;
                leaving_dialog = true;
                last_output = Instant::now();
            }
        } else if leaving_dialog && !exiting && screen.ready() {
            write_command(writer, b"/exit\r")?;
            exiting = true;
        }
    }
}

fn write_command(writer: &mut Box<dyn Write + Send>, bytes: &[u8]) -> Result<()> {
    writer
        .write_all(bytes)
        .and_then(|_| writer.flush())
        .map_err(|_| unavailable("terminal write failed"))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    #[cfg(unix)]
    fn idle_terminal_stays_nonblocking_while_slave_is_held_open() {
        // Same EOF condition as a descendant retaining the slave: there is no
        // output, but the slave remains open. Collection must not wait for EOF.
        let pty = native_pty_system().openpty(PtySize::default()).unwrap();
        nonblocking(pty.master.as_ref()).unwrap();
        let mut reader = pty.master.try_clone_reader().unwrap();
        let started = Instant::now();
        let error = reader.read(&mut [0_u8; 8]).unwrap_err();
        assert_eq!(error.kind(), std::io::ErrorKind::WouldBlock);
        assert!(started.elapsed() < Duration::from_millis(100));
        drop(pty.slave);
    }

    #[cfg(unix)]
    fn fake(mode: &str, timeout: Duration) -> (tempfile::TempDir, ClaudeUsageProbe) {
        use std::os::unix::fs::PermissionsExt;
        let directory = tempfile::tempdir().unwrap();
        let executable = directory.path().join(mode);
        std::fs::write(
            &executable,
            include_str!("../../tests/fixtures/claude_fake.py"),
        )
        .unwrap();
        std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o700)).unwrap();
        let mut config = ProbeConfig::new(executable, directory.path().to_owned());
        config.timeout = timeout;
        (directory, ClaudeUsageProbe::new(config))
    }
    #[test]
    #[cfg(unix)]
    fn offline_pty_proves_refresh_redraw_and_command_sequence() {
        let (_directory, probe) = fake("success", Duration::from_secs(5));
        let result = probe.read().unwrap();
        assert_eq!(result[0].remaining_percent, 66.0);
        assert_eq!(result[1].remaining_percent, 97.0);
    }
    #[test]
    #[cfg(unix)]
    fn offline_pty_cache_auth_error_and_hung_child_fail_closed_and_exit() {
        for mode in ["cache", "auth", "failure", "timeout"] {
            let (_directory, probe) = fake(mode, Duration::from_millis(900));
            let start = Instant::now();
            assert!(probe.read().is_err(), "{mode}");
            assert!(start.elapsed() < Duration::from_secs(3), "{mode}");
        }
    }
    #[test]
    fn rejects_relative_paths_and_unbounded_timeout_before_spawn() {
        let mut config = ProbeConfig::new("claude".into(), "/tmp".into());
        assert!(ClaudeUsageProbe::new(config.clone()).read().is_err());
        config.executable = "/does-not-exist".into();
        config.timeout = Duration::from_secs(31);
        assert!(ClaudeUsageProbe::new(config).read().is_err());
    }
    #[test]
    fn rejects_concurrent_read() {
        let probe = ClaudeUsageProbe::new(ProbeConfig::new("/missing".into(), "/tmp".into()));
        let _lock = probe.serial.lock().unwrap();
        assert!(
            probe
                .read()
                .unwrap_err()
                .to_string()
                .contains("already running")
        );
    }
}
