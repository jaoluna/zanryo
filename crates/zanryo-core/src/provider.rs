use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ProviderId {
    #[serde(rename = "openai")]
    OpenAi,
    #[serde(rename = "claude")]
    Claude,
}

impl ProviderId {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::OpenAi => "openai",
            Self::Claude => "claude",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ProviderInstallation {
    pub provider: ProviderId,
    pub executable_path: PathBuf,
}

pub fn discover_installed_providers() -> Vec<ProviderInstallation> {
    let mut installations = Vec::new();

    if let Some(executable_path) = crate::transport::resolve_codex_path() {
        installations.push(ProviderInstallation {
            provider: ProviderId::OpenAi,
            executable_path,
        });
    }
    if let Some(executable_path) = resolve_executable(claude_candidates()) {
        installations.push(ProviderInstallation {
            provider: ProviderId::Claude,
            executable_path,
        });
    }

    installations
}

pub(crate) fn resolve_executable<I, P>(candidates: I) -> Option<PathBuf>
where
    I: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    candidates.into_iter().find_map(|candidate| {
        let candidate = candidate.as_ref();
        is_executable_file(candidate)
            .then(|| candidate.canonicalize().ok())
            .flatten()
    })
}

#[cfg(unix)]
fn is_executable_file(path: &Path) -> bool {
    fs::metadata(path)
        .is_ok_and(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
}

#[cfg(not(unix))]
fn is_executable_file(_path: &Path) -> bool {
    false
}

#[cfg(test)]
fn discover_from_candidates(
    openai_candidates: &[PathBuf],
    claude_candidates: &[PathBuf],
) -> Vec<ProviderInstallation> {
    let mut installations = Vec::new();

    if let Some(executable_path) = resolve_executable(openai_candidates) {
        installations.push(ProviderInstallation {
            provider: ProviderId::OpenAi,
            executable_path,
        });
    }
    if let Some(executable_path) = resolve_executable(claude_candidates) {
        installations.push(ProviderInstallation {
            provider: ProviderId::Claude,
            executable_path,
        });
    }

    installations
}

fn claude_candidates_from(path: Option<OsString>, home: Option<&Path>) -> Vec<PathBuf> {
    let mut candidates = path
        .as_deref()
        .map(env::split_paths)
        .into_iter()
        .flatten()
        .map(|directory| directory.join("claude"))
        .collect::<Vec<_>>();

    if let Some(home) = home.filter(|home| !home.as_os_str().is_empty()) {
        candidates.push(home.join(".local/bin/claude"));
        candidates.push(home.join(".claude/local/claude"));
    }
    candidates.push(PathBuf::from("/opt/homebrew/bin/claude"));
    candidates.push(PathBuf::from("/usr/local/bin/claude"));
    candidates
}

fn claude_candidates() -> Vec<PathBuf> {
    let home = env::var_os("HOME").map(PathBuf::from);
    claude_candidates_from(env::var_os("PATH"), home.as_deref())
}

#[cfg(test)]
mod tests {
    use std::ffi::OsString;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::path::{Path, PathBuf};

    use super::*;

    fn executable(path: PathBuf) -> PathBuf {
        fs::write(&path, "").unwrap();
        let mut permissions = fs::metadata(&path).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&path, permissions).unwrap();
        path
    }

    #[test]
    fn discovery_keeps_openai_before_claude_and_omits_missing_tools() {
        let directory = tempfile::tempdir().unwrap();
        let openai = executable(directory.path().join("codex"));
        let missing_claude = directory.path().join("claude");

        let found = discover_from_candidates(std::slice::from_ref(&openai), &[missing_claude]);

        assert_eq!(
            found,
            vec![ProviderInstallation {
                provider: ProviderId::OpenAi,
                executable_path: openai.canonicalize().unwrap(),
            }]
        );
    }

    #[test]
    fn resolver_accepts_an_executable_symlink_and_canonicalizes_its_target() {
        let directory = tempfile::tempdir().unwrap();
        let non_executable = directory.path().join("not-executable");
        fs::write(&non_executable, "").unwrap();
        let mut permissions = fs::metadata(&non_executable).unwrap().permissions();
        permissions.set_mode(0o644);
        fs::set_permissions(&non_executable, permissions).unwrap();

        let target = executable(directory.path().join("codex"));
        let symlink = directory.path().join("codex-link");
        std::os::unix::fs::symlink(&target, &symlink).unwrap();

        assert_eq!(
            resolve_executable([non_executable, symlink]),
            Some(target.canonicalize().unwrap())
        );
    }

    #[test]
    fn claude_candidates_keep_path_precedence_before_user_and_system_locations() {
        let home = PathBuf::from("/Users/tester");

        assert_eq!(
            claude_candidates_from(Some(OsString::from("/first/bin:/second/bin")), Some(&home)),
            vec![
                PathBuf::from("/first/bin/claude"),
                PathBuf::from("/second/bin/claude"),
                home.join(".local/bin/claude"),
                home.join(".claude/local/claude"),
                PathBuf::from("/opt/homebrew/bin/claude"),
                PathBuf::from("/usr/local/bin/claude"),
            ]
        );
    }

    #[test]
    fn empty_home_omits_relative_claude_candidates() {
        assert_eq!(
            claude_candidates_from(Some(OsString::from("/first/bin")), Some(Path::new(""))),
            vec![
                PathBuf::from("/first/bin/claude"),
                PathBuf::from("/opt/homebrew/bin/claude"),
                PathBuf::from("/usr/local/bin/claude"),
            ]
        );
    }
}
