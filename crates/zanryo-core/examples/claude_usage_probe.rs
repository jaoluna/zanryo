//! Explicit canary only: no DB, polling, account identifiers or raw output.
use std::{path::PathBuf, time::Instant};
use zanryo_core::claude::{ClaudeUsageProbe, ProbeConfig};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args.len() != 2 {
        return Err("usage: claude_usage_probe /absolute/claude /already/trusted/directory".into());
    }
    let started = Instant::now();
    let limits = ClaudeUsageProbe::new(ProbeConfig::new(
        PathBuf::from(&args[0]),
        PathBuf::from(&args[1]),
    ))
    .read()?;
    println!("{}", serde_json::to_string_pretty(&limits)?);
    eprintln!(
        "probe completed in {:.2}s; no database opened",
        started.elapsed().as_secs_f64()
    );
    Ok(())
}
