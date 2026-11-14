use chrono::{DateTime, Datelike, Duration, NaiveDate, NaiveTime, TimeZone, Utc};
use chrono_tz::Tz;

use crate::{LimitKind, ProviderId, RateLimit, Result, ZanryoError};

fn invalid() -> ZanryoError {
    // Never echo raw terminal text: it can contain account or workspace data.
    ZanryoError::Protocol("Claude usage format or reset is unsupported".into())
}

/// Decode a completed, reconstructed terminal frame, never a concatenated log.
/// Freshness/refresh completion must be proved by the transport before use.
pub fn decode_usage_screen(screen: &str, observed: DateTime<Utc>) -> Result<Vec<RateLimit>> {
    let lines: Vec<_> = screen.lines().map(str::trim).collect();
    if !lines
        .iter()
        .any(|line| line.starts_with("Settings ") && line.contains("Usage"))
        || !lines.contains(&"Esc to cancel")
        || screen.contains("Refreshing")
    {
        return Err(invalid());
    }
    let mut limits = Vec::new();
    for (label, kind, id) in [
        ("Current session", LimitKind::FiveHour, "claude_five_hour"),
        (
            "Current week (all models)",
            LimitKind::Weekly,
            "claude_weekly",
        ),
        ("Current week (Fable)", LimitKind::Fable, "claude_fable"),
    ] {
        let positions: Vec<_> = lines
            .iter()
            .enumerate()
            .filter(|(_, line)| **line == label)
            .map(|(index, _)| index)
            .collect();
        if positions.len() > 1 {
            return Err(invalid());
        }
        let Some(index) = positions.first().copied() else {
            continue;
        };
        let used = parse_percentage(lines.get(index + 1).copied().ok_or_else(invalid)?)?;
        let resets_at = parse_reset(
            lines.get(index + 2).copied().ok_or_else(invalid)?,
            &kind,
            observed,
        )?;
        limits.push(RateLimit::new(
            ProviderId::Claude,
            kind,
            id,
            100.0 - used,
            resets_at,
            observed,
        )?);
    }
    if limits.is_empty() {
        return Err(invalid());
    }
    Ok(limits)
}

fn parse_percentage(line: &str) -> Result<f64> {
    let value = line.strip_suffix(" used").ok_or_else(invalid)?;
    let parts: Vec<_> = value.split_whitespace().collect();
    if !(1..=2).contains(&parts.len()) {
        return Err(invalid());
    }
    let parse = |part: &str| -> Result<f64> {
        let value: f64 = part
            .strip_suffix('%')
            .ok_or_else(invalid)?
            .parse()
            .map_err(|_| invalid())?;
        if !value.is_finite() || !(0.0..=100.0).contains(&value) {
            return Err(invalid());
        }
        Ok(value)
    };
    let first = parse(parts[0])?;
    if parts.len() == 2 && parse(parts[1])? != first {
        return Err(invalid());
    }
    Ok(first)
}

fn parse_reset(line: &str, kind: &LimitKind, observed: DateTime<Utc>) -> Result<DateTime<Utc>> {
    let rest = line.strip_prefix("Resets ").ok_or_else(invalid)?;
    let (clock, zone) = rest.rsplit_once(" (").ok_or_else(invalid)?;
    let zone: Tz = zone
        .strip_suffix(')')
        .ok_or_else(invalid)?
        .parse()
        .map_err(|_| invalid())?;
    let local = observed.with_timezone(&zone);
    let time_of = |text: &str| -> Result<NaiveTime> {
        let (clock, pm) = if let Some(clock) = text.strip_suffix("pm") {
            (clock, true)
        } else if let Some(clock) = text.strip_suffix("am") {
            (clock, false)
        } else {
            return Err(invalid());
        };
        let (hour, minute) = clock.split_once(':').unwrap_or((clock, "00"));
        if !hour.chars().all(|c| c.is_ascii_digit())
            || !minute.chars().all(|c| c.is_ascii_digit())
            || minute.len() != 2
        {
            return Err(invalid());
        }
        let hour: u32 = hour.parse().map_err(|_| invalid())?;
        let minute: u32 = minute.parse().map_err(|_| invalid())?;
        if !(1..=12).contains(&hour) {
            return Err(invalid());
        }
        NaiveTime::from_hms_opt(hour % 12 + if pm { 12 } else { 0 }, minute, 0).ok_or_else(invalid)
    };
    let candidates = if let Some((month_day, time)) = clock.split_once(" at ") {
        if !matches!(kind, LimitKind::Weekly | LimitKind::Fable) {
            return Err(invalid());
        }
        let time = time_of(time)?;
        [local.year(), local.year() + 1]
            .iter()
            .filter_map(|year| {
                NaiveDate::parse_from_str(&format!("{year} {month_day}"), "%Y %b %d")
                    .ok()
                    .and_then(|day| zone.from_local_datetime(&day.and_time(time)).single())
            })
            .collect::<Vec<_>>()
    } else {
        if *kind != LimitKind::FiveHour {
            return Err(invalid());
        }
        let time = time_of(clock)?;
        [0, 1]
            .iter()
            .filter_map(|days| {
                local
                    .date_naive()
                    .checked_add_signed(Duration::days(*days))
                    .and_then(|day| zone.from_local_datetime(&day.and_time(time)).single())
            })
            .collect()
    };
    let max_ahead = if *kind == LimitKind::FiveHour {
        Duration::hours(5)
    } else {
        Duration::days(7)
    } + Duration::minutes(2);
    candidates
        .into_iter()
        .map(|date| date.with_timezone(&Utc))
        .find(|date| *date > observed && *date <= observed + max_ahead)
        .ok_or_else(invalid)
}

/// Any well-formed `major.minor.patch` CLI banner. The version is not pinned:
/// the safe-mode prompt checks, `blocked` and the strict usage-frame parser fail
/// closed when a future CLI changes its grammar, so the reading turns stale
/// instead of persisting a wrong value.
fn claude_cli_banner(text: &str) -> bool {
    text.split("Claude Code v").skip(1).any(|rest| {
        let end = rest
            .find(|c: char| !(c.is_ascii_digit() || c == '.'))
            .unwrap_or(rest.len());
        let parts: Vec<_> = rest[..end].split('.').collect();
        parts.len() == 3
            && parts
                .iter()
                .all(|part| !part.is_empty() && part.chars().all(|c| c.is_ascii_digit()))
    })
}

/// The CLI's own notice that the login will expire. The session still works, so
/// only this exact grammar is exempt from `blocked`; any other login text fails closed.
fn login_expiry_notice(line: &str) -> bool {
    let Some(rest) = line
        .trim()
        .strip_prefix("warning: Your login expires in ")
        .and_then(|rest| rest.strip_suffix(" · run /login to renew"))
    else {
        return false;
    };
    let parts: Vec<_> = rest.split(' ').collect();
    matches!(
        parts.as_slice(),
        [count, "day" | "days"]
            if !count.is_empty() && count.chars().all(|c| c.is_ascii_digit())
    )
}

/// Bounded terminal state plus proof that this request saw a refresh transition.
pub(super) struct UsageScreen {
    parser: vt100::Parser,
    requested: bool,
    saw_refresh: bool,
    bytes: usize,
}

impl UsageScreen {
    pub fn new() -> Self {
        Self {
            parser: vt100::Parser::new(80, 160, 0),
            requested: false,
            saw_refresh: false,
            bytes: 0,
        }
    }
    pub fn mark_requested(&mut self) {
        self.requested = true;
        self.saw_refresh = false;
    }
    pub fn feed(&mut self, bytes: &[u8]) -> Result<()> {
        self.bytes += bytes.len();
        if self.bytes > 256 * 1024 {
            return Err(invalid());
        }
        // Observe intermediate redraws even when refresh and completion arrive
        // together in one read. UTF-8/escape state stays inside vt100.
        for byte in bytes {
            self.parser.process(&[*byte]);
            // "Refreshing" may be erased by an inline ANSI redraw before any
            // newline arrives. Observe its final byte, not only chunk boundaries.
            if *byte == b'g' || *byte == b'\n' {
                self.observe_refresh();
            }
        }
        self.observe_refresh();
        Ok(())
    }
    fn observe_refresh(&mut self) {
        if self.requested && self.contents().contains("Refreshing") {
            self.saw_refresh = true;
        }
    }
    pub fn contents(&self) -> String {
        self.parser.screen().contents()
    }
    pub fn ready(&self) -> bool {
        let text = self.contents();
        // Any CLI version, but only on the recognised safe-mode prompt.
        claude_cli_banner(&text)
            && text.contains("Safe mode:")
            && text.contains("manual mode on")
            && text.lines().last().is_some_and(|line| line.trim() == "$")
    }
    pub fn blocked(&self) -> bool {
        let text = self
            .contents()
            .lines()
            .filter(|line| !login_expiry_notice(line))
            .collect::<Vec<_>>()
            .join("\n")
            .to_lowercase();
        [
            "trust this",
            "do you trust",
            "login",
            "log in",
            "sign in",
            "failed to",
            "error:",
            "make auto mode",
        ]
        .iter()
        .any(|value| text.contains(value))
    }
    pub fn completed(&self, now: DateTime<Utc>) -> Result<Vec<RateLimit>> {
        if !self.requested || !self.saw_refresh || self.blocked() {
            return Err(invalid());
        }
        decode_usage_screen(&self.contents(), now)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 9, 25, 20, 30, 0).unwrap()
    }
    fn frame(session: &str, week: &str) -> String {
        format!(
            "Settings  Status   Config   Usage   Stats\n{session}{week}Usage credits\nUsage credits are off\nEsc to cancel"
        )
    }
    fn session(percent: &str) -> String {
        format!("Current session\n{percent}\nResets 6pm (America/Sao_Paulo)\n")
    }
    fn week() -> String {
        "Current week (all models)\n3% 3% used\nResets Sep 30 at 7pm (America/Sao_Paulo)\n".into()
    }
    #[test]
    fn normalizes_once_and_preserves_windows() {
        let limits = decode_usage_screen(&frame(&session("34% 34% used"), &week()), now()).unwrap();
        assert_eq!(limits.len(), 2);
        assert_eq!(limits[0].remaining_percent, 66.0);
        assert_eq!(limits[1].remaining_percent, 97.0);
        assert_eq!(
            limits[0].resets_at,
            Utc.with_ymd_and_hms(2026, 9, 25, 21, 0, 0).unwrap()
        );
        assert!(
            limits
                .iter()
                .all(|limit| limit.provider == ProviderId::Claude && limit.observed_at == now())
        );
    }
    #[test]
    fn missing_windows_are_not_zero_or_required() {
        assert_eq!(
            decode_usage_screen(&frame(&session("0% used"), ""), now()).unwrap()[0]
                .remaining_percent,
            100.0
        );
        assert_eq!(
            decode_usage_screen(&frame("", &week()), now())
                .unwrap()
                .len(),
            1
        );
        assert!(decode_usage_screen(&frame("", ""), now()).is_err());
    }
    #[test]
    fn fable_is_a_separate_optional_weekly_window() {
        let fable = "Current week (Fable)\n18% used\nResets Sep 29 at 8pm (America/Sao_Paulo)\n";
        let limits =
            decode_usage_screen(&frame(&session("34% used"), &(week() + fable)), now()).unwrap();
        assert_eq!(limits.len(), 3);
        assert_eq!(limits[2].kind, LimitKind::Fable);
        assert_eq!(limits[2].limit_id, "claude_fable");
        assert_eq!(limits[2].remaining_percent, 82.0);
        assert_ne!(limits[1].resets_at, limits[2].resets_at);
        let only = decode_usage_screen(&frame("", fable), now()).unwrap();
        assert_eq!(only.len(), 1);
        assert_eq!(only[0].kind, LimitKind::Fable);
        assert!(decode_usage_screen(&frame("", &(fable.to_owned() + fable)), now()).is_err());
        assert!(decode_usage_screen(&frame("", &fable.replace("18%", "101%")), now()).is_err());
    }
    #[test]
    fn bounds_invalid_and_conflicting_percentages_fail_closed() {
        for value in [
            "101% used",
            "-1% used",
            "NaN% used",
            "34% 33% used",
            "unknown",
            "34% left",
        ] {
            assert!(
                decode_usage_screen(&frame(&session(value), ""), now()).is_err(),
                "{value}"
            );
        }
        assert_eq!(
            decode_usage_screen(&frame(&session("100% used"), ""), now()).unwrap()[0]
                .remaining_percent,
            0.0
        );
    }
    #[test]
    fn ambiguous_reset_and_incomplete_frames_rejected() {
        let valid = frame(&session("34% used"), &week());
        for input in [
            valid.replace("America/Sao_Paulo", "Invalid/Zone"),
            valid.replace("6pm", "4pm"),
            valid.replace("Esc to cancel", "Refreshing…"),
            valid.replace("6pm", "36pm"),
            valid
                .replace("Current session", "Unknown session")
                .replace("Current week (all models)", "Other week"),
        ] {
            assert!(decode_usage_screen(&input, now()).is_err());
        }
    }
    #[test]
    fn reset_crosses_year_but_cannot_be_months_away() {
        let observed = Utc.with_ymd_and_hms(2026, 12, 30, 20, 0, 0).unwrap();
        let input = frame("", &week().replace("Sep 30", "Jan 2"));
        assert_eq!(
            decode_usage_screen(&input, observed).unwrap()[0]
                .resets_at
                .year(),
            2027
        );
        assert!(decode_usage_screen(&input, now()).is_err());
    }
    #[test]
    fn cache_never_fresh_and_ansi_redraw_replaces_old_values() {
        let mut screen = UsageScreen::new();
        screen.mark_requested();
        let cached = frame(&session("33% 33% used"), &week());
        screen
            .feed(cached.replace('\n', "\r\n").as_bytes())
            .unwrap();
        assert!(screen.completed(now()).is_err());
        screen.feed(b"\r\nRefreshing\xe2\x80\xa6\r\n").unwrap();
        let fresh = format!(
            "\x1b[2J\x1b[H{}",
            frame(&session("34% 34% used"), &week()).replace('\n', "\r\n")
        );
        for byte in fresh.as_bytes() {
            screen.feed(&[*byte]).unwrap();
        }
        assert_eq!(screen.completed(now()).unwrap()[0].remaining_percent, 66.0);
    }
    #[test]
    fn refresh_and_completion_in_same_chunk_still_observed() {
        let mut screen = UsageScreen::new();
        screen.mark_requested();
        screen
            .feed(
                format!(
                    "Refreshing…\r\n\x1b[2J\x1b[H{}",
                    frame(&session("34% used"), &week()).replace('\n', "\r\n")
                )
                .as_bytes(),
            )
            .unwrap();
        assert!(screen.completed(now()).is_ok());
    }
    #[test]
    fn inline_refresh_erased_without_newline_is_observed() {
        let mut screen = UsageScreen::new();
        screen.mark_requested();
        let redraw = format!(
            "Refreshing…\x1b[2J\x1b[H{}",
            frame(&session("34% used"), &week()).replace('\n', "\r\n")
        );
        screen.feed(redraw.as_bytes()).unwrap();
        assert!(screen.completed(now()).is_ok());
    }
    #[test]
    fn auth_error_and_oversized_output_never_accepted() {
        let mut screen = UsageScreen::new();
        screen.feed(b"Please log in").unwrap();
        assert!(screen.blocked());
        assert!(screen.feed(&vec![b'x'; 256 * 1024]).is_err());
    }

    #[test]
    fn login_expiry_warning_is_not_a_login_prompt() {
        let prompt = |notice: &str| {
            let mut screen = UsageScreen::new();
            let text = format!(
                "Claude Code v2.1.303\r\nwarning: Safe mode: all customizations are disabled\r\n{notice}\r\nmanual mode on\r\n$"
            );
            screen.feed(text.as_bytes()).unwrap();
            screen
        };
        for notice in [
            "warning: Your login expires in 3 days · run /login to renew",
            "warning: Your login expires in 1 day · run /login to renew",
        ] {
            let screen = prompt(notice);
            assert!(!screen.blocked(), "{notice}");
            assert!(screen.ready(), "{notice}");
        }
        for notice in [
            "warning: Your login expired · run /login to renew",
            "warning: Your login expires in soon · run /login to renew",
            "warning: Your login expires in 3 hours · run /login to renew",
            "warning: Your login expires in 3 days · run /login to renew now",
            "Please log in. warning: Your login expires in 3 days · run /login to renew",
            "warning: Your login expires in 3 days · run /login to renew\r\nPlease log in",
            "Please run /login",
        ] {
            assert!(prompt(notice).blocked(), "{notice}");
        }

        // The usage dialog still completes with the notice above it on screen.
        let mut screen = prompt("warning: Your login expires in 3 days · run /login to renew");
        screen.mark_requested();
        let dialog = format!(
            "\r\nRefreshing…\r\x1b[2K{}",
            frame(&session("34% used"), &week()).replace('\n', "\r\n")
        );
        screen.feed(dialog.as_bytes()).unwrap();
        assert!(screen.contents().contains("Your login expires in 3 days"));
        assert_eq!(screen.completed(now()).unwrap().len(), 2);
    }

    #[test]
    fn prompt_accepts_any_well_formed_cli_version() {
        let ready = |version: &str| {
            let mut screen = UsageScreen::new();
            let prompt = format!(
                "Claude Code v{version}\r\nSafe mode: customizations disabled\r\nmanual mode on\r\n$"
            );
            screen.feed(prompt.as_bytes()).unwrap();
            screen.ready()
        };
        for version in [
            "2.1.282",
            "2.1.319",
            "2.1.320",
            "2.2.0",
            "3.0.0",
            "10.20.300",
        ] {
            assert!(ready(version), "{version}");
        }
        for malformed in [
            "", "2", "2.1", "2.1.", ".2.1", "2..1", "2.1.3.4", "v2.1.3", "x.y.z",
        ] {
            assert!(!ready(malformed), "{malformed:?}");
        }
    }
}
