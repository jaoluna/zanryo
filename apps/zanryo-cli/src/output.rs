use chrono::{DateTime, Utc};
use zanryo_core::{
    ForecastConfidence, ForecastReport, ForecastStatus, Freshness, QuotaSnapshot, RateLimit,
};

pub fn format_snapshot(snapshot: &QuotaSnapshot, now: DateTime<Utc>) -> String {
    let mut lines = vec![format_limit("Weekly", &snapshot.weekly, now)];

    if let Some(spark) = &snapshot.spark {
        lines.push(format_limit("Spark", spark, now));
    }
    if snapshot.freshness == Freshness::Stale {
        lines.push("Data is stale.".to_owned());
    }

    lines.join("\n")
}

pub fn format_history(limits: &[RateLimit]) -> String {
    if limits.is_empty() {
        return "No history yet.".to_owned();
    }

    limits
        .iter()
        .map(|limit| {
            format!(
                "{} · {} · {}% left",
                limit.observed_at.format("%Y-%m-%d %H:%M UTC"),
                limit.limit_id,
                format_percent(limit.remaining_percent)
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}

pub fn format_forecast(report: &ForecastReport, now: DateTime<Utc>) -> String {
    if report.status == ForecastStatus::CollectingHistory {
        return "Collecting history".to_owned();
    }

    let pace = report.consumed_per_day.unwrap_or_default();
    let sustainable = report.sustainable_per_day.unwrap_or_default();
    let depletion = report
        .estimated_depletion_at
        .map(|at| {
            format!(
                "Estimated depletion in {}",
                format_duration(at.signed_duration_since(now))
            )
        })
        .unwrap_or_else(|| "Estimated depletion not expected at current pace".to_owned());
    let confidence = match report.confidence {
        ForecastConfidence::Collecting => "collecting",
        ForecastConfidence::Low => "low",
        ForecastConfidence::Medium => "medium",
        ForecastConfidence::High => "high",
    };

    format!(
        "Pace {pace:.1} pp/day · sustainable {sustainable:.1} pp/day\n\
         {depletion} · {confidence} confidence"
    )
}

fn format_limit(label: &str, limit: &RateLimit, now: DateTime<Utc>) -> String {
    format!(
        "{label} {}% left · reset in {}",
        format_percent(limit.remaining_percent),
        format_duration(limit.resets_at.signed_duration_since(now))
    )
}

fn format_percent(value: f64) -> String {
    if value.fract().abs() < f64::EPSILON {
        format!("{value:.0}")
    } else {
        format!("{value:.1}")
    }
}

fn format_duration(duration: chrono::Duration) -> String {
    let total_minutes = duration.num_minutes().max(0);
    let days = total_minutes / (24 * 60);
    let hours = total_minutes % (24 * 60) / 60;
    let minutes = total_minutes % 60;
    let mut parts = Vec::new();

    if days > 0 {
        parts.push(format!("{days}d"));
    }
    if hours > 0 {
        parts.push(format!("{hours}h"));
    }
    if parts.is_empty() {
        parts.push(format!("{minutes}m"));
    }

    parts.join(" ")
}

#[cfg(test)]
mod tests {
    use super::{format_forecast, format_snapshot};
    use chrono::{Duration, TimeZone, Utc};
    use zanryo_core::{
        ChartSeries, ForecastConfidence, ForecastRange, ForecastReport, ForecastStatus, Freshness,
        LimitKind, ProviderId, QuotaSnapshot, RateLimit,
    };

    #[test]
    fn formats_weekly_and_spark_summary() {
        let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
        let weekly = RateLimit::new(
            ProviderId::OpenAi,
            LimitKind::Weekly,
            "codex",
            15.0,
            now + Duration::days(5) + Duration::hours(3),
            now,
        )
        .unwrap();
        let spark = RateLimit::new(
            ProviderId::OpenAi,
            LimitKind::Spark,
            "codex_bengalfox",
            72.0,
            now + Duration::days(6),
            now,
        )
        .unwrap();
        let snapshot =
            QuotaSnapshot::from_limits(ProviderId::OpenAi, vec![weekly, spark], Freshness::Fresh)
                .unwrap();

        assert_eq!(
            format_snapshot(&snapshot, now),
            "Weekly 15% left · reset in 5d 3h\nSpark 72% left · reset in 6d"
        );
    }

    #[test]
    fn formats_estimated_forecast_without_fake_certainty() {
        let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
        let report = ForecastReport {
            status: ForecastStatus::Estimated,
            confidence: ForecastConfidence::Medium,
            consumed_per_day: Some(8.5),
            sustainable_per_day: Some(3.0),
            pace_difference: Some(5.5),
            estimated_depletion_at: Some(now + Duration::days(2)),
            rate_range: Some(ForecastRange {
                low: 7.0,
                high: 10.0,
            }),
            chart: ChartSeries::default(),
        };

        assert_eq!(
            format_forecast(&report, now),
            "Pace 8.5 pp/day · sustainable 3.0 pp/day\n\
             Estimated depletion in 2d · medium confidence"
        );
    }

    #[test]
    fn formats_collecting_history() {
        let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
        let report = ForecastReport {
            status: ForecastStatus::CollectingHistory,
            confidence: ForecastConfidence::Collecting,
            consumed_per_day: None,
            sustainable_per_day: None,
            pace_difference: None,
            estimated_depletion_at: None,
            rate_range: None,
            chart: ChartSeries::default(),
        };

        assert_eq!(format_forecast(&report, now), "Collecting history");
    }
}
