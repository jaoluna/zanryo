mod output;

use std::error::Error;
use std::io::{self, Write};
use std::path::Path;
use std::process::{Command as ProcessCommand, ExitCode};
use std::time::Duration;

use chrono::{Duration as ChronoDuration, Utc};
use clap::{Parser, Subcommand};
use serde_json::json;
use zanryo_core::{
    CodexAppServer, HistoryRepository, QuotaService, ZanryoError, resolve_codex_path,
};

use crate::output::{format_forecast, format_history, format_snapshot};

type CliResult<T> = std::result::Result<T, Box<dyn Error + Send + Sync>>;

#[derive(Parser)]
#[command(name = "zanryo", version, about = "Lightweight Codex quota monitor")]
struct Cli {
    #[arg(long, global = true)]
    json: bool,
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// Continuously refresh quota data.
    Watch,
    /// Show locally recorded quota samples.
    History {
        #[arg(long, default_value_t = 7, value_parser = parse_days)]
        days: u16,
    },
    /// Check Codex and local storage availability.
    Doctor,
}

#[tokio::main]
async fn main() -> ExitCode {
    match run(Cli::parse()).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("zanryo: {error}");
            ExitCode::FAILURE
        }
    }
}

async fn run(cli: Cli) -> CliResult<()> {
    match cli.command {
        Some(Command::Doctor) => run_doctor(cli.json),
        Some(Command::History { days }) => run_history(days, cli.json),
        Some(Command::Watch) => run_watch(cli.json).await,
        None => run_summary(cli.json).await,
    }
}

async fn run_summary(json_output: bool) -> CliResult<()> {
    let service = build_service().await?;
    let now = Utc::now();
    let dashboard = service.refresh_dashboard(now).await?;

    if json_output {
        println!("{}", serde_json::to_string_pretty(&dashboard)?);
    } else {
        println!(
            "{}\n{}",
            format_snapshot(&dashboard.quota, now),
            format_forecast(&dashboard.forecast, now)
        );
    }
    Ok(())
}

async fn run_watch(json_output: bool) -> CliResult<()> {
    let service = build_service().await?;

    loop {
        let now = Utc::now();
        let dashboard = service.refresh_dashboard(now).await?;
        print!("\x1b[2J\x1b[H");
        if json_output {
            println!("{}", serde_json::to_string_pretty(&dashboard)?);
        } else {
            println!(
                "{}\n{}",
                format_snapshot(&dashboard.quota, now),
                format_forecast(&dashboard.forecast, now)
            );
        }
        io::stdout().flush()?;

        tokio::select! {
            result = tokio::signal::ctrl_c() => {
                result?;
                break;
            }
            () = tokio::time::sleep(Duration::from_secs(15)) => {}
        }
    }

    Ok(())
}

fn run_history(days: u16, json_output: bool) -> CliResult<()> {
    let history = HistoryRepository::open_default()?;
    let limits = history.limits_since(Utc::now() - ChronoDuration::days(i64::from(days)))?;

    if json_output {
        println!("{}", serde_json::to_string_pretty(&limits)?);
    } else {
        println!("{}", format_history(&limits));
    }
    Ok(())
}

fn run_doctor(json_output: bool) -> CliResult<()> {
    let codex_path = resolve_codex_path();
    let app_server = codex_path
        .as_deref()
        .is_some_and(codex_app_server_help_succeeds);
    let storage_path = HistoryRepository::default_path();
    let storage_writable = HistoryRepository::open_default().is_ok();
    let healthy = codex_path.is_some() && app_server && storage_writable;
    let report = json!({
        "codex": {
            "found": codex_path.is_some(),
            "path": codex_path,
            "app_server": app_server
        },
        "storage": {
            "path": storage_path.as_ref().ok(),
            "writable": storage_writable
        },
        "status": if healthy { "ok" } else { "degraded" }
    });

    if json_output {
        println!("{}", serde_json::to_string_pretty(&report)?);
    } else {
        println!(
            "Codex: {}\nStorage: {}\nStatus: {}",
            if app_server { "ready" } else { "unavailable" },
            if storage_writable {
                "writable"
            } else {
                "unavailable"
            },
            report["status"].as_str().unwrap_or("degraded")
        );
    }
    Ok(())
}

async fn build_service() -> CliResult<QuotaService<CodexAppServer>> {
    let codex_path = resolve_codex_path().ok_or_else(|| {
        ZanryoError::Transport(
            "Codex executable not found; set CODEX_PATH or install Codex".to_owned(),
        )
    })?;
    let source = CodexAppServer::spawn(codex_path).await?;
    let history = HistoryRepository::open_default()?;
    Ok(QuotaService::new(source, history))
}

fn codex_app_server_help_succeeds(path: &Path) -> bool {
    ProcessCommand::new(path)
        .args(["app-server", "--help"])
        .output()
        .is_ok_and(|output| output.status.success())
}

fn parse_days(value: &str) -> std::result::Result<u16, String> {
    let days = value
        .parse::<u16>()
        .map_err(|_| "days must be a positive integer".to_owned())?;

    if days == 0 {
        Err("days must be at least 1".to_owned())
    } else {
        Ok(days)
    }
}
