use assert_cmd::cargo::cargo_bin_cmd;
use predicates::prelude::*;

#[test]
fn help_lists_the_small_command_surface() {
    cargo_bin_cmd!("zanryo")
        .arg("--help")
        .assert()
        .success()
        .stdout(predicate::str::contains("watch"))
        .stdout(predicate::str::contains("history"))
        .stdout(predicate::str::contains("doctor"))
        .stdout(predicate::str::contains("--json"));
}

#[test]
fn doctor_json_always_has_stable_top_level_keys() {
    let output = cargo_bin_cmd!("zanryo")
        .args(["doctor", "--json"])
        .output()
        .unwrap();
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();

    assert!(value.get("codex").is_some());
    assert!(value.get("storage").is_some());
    assert!(value.get("status").is_some());
}

#[test]
fn history_rejects_zero_days() {
    cargo_bin_cmd!("zanryo")
        .args(["history", "--days", "0"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("days must be at least 1"));
}
