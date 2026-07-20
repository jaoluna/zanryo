use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::{LimitKind, RateLimit};

const MINIMUM_SAMPLES: usize = 3;
const MINIMUM_SPAN_MINUTES: i64 = 30;
const RECENT_HOURS: i64 = 24;
const MAX_RECENT_WEIGHT: f64 = 0.70;
const MAX_RECENT_GAP_HOURS: i64 = 6;
const DISCONTINUITY_POINTS: f64 = 1.0;
const MINIMUM_RATE: f64 = 0.05;
const SECONDS_PER_DAY: f64 = 86_400.0;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ForecastStatus {
    CollectingHistory,
    Estimated,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ForecastConfidence {
    Collecting,
    Low,
    Medium,
    High,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ForecastRange {
    pub low: f64,
    pub high: f64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ChartPoint {
    pub at: DateTime<Utc>,
    pub remaining_percent: f64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ForecastPoint {
    pub at: DateTime<Utc>,
    pub remaining_percent: f64,
    pub uncertainty: ForecastRange,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct ChartSeries {
    pub observed: Vec<ChartPoint>,
    pub forecast: Vec<ForecastPoint>,
    pub sustainable: Vec<ChartPoint>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ForecastReport {
    pub status: ForecastStatus,
    pub confidence: ForecastConfidence,
    pub consumed_per_day: Option<f64>,
    pub sustainable_per_day: Option<f64>,
    pub pace_difference: Option<f64>,
    pub estimated_depletion_at: Option<DateTime<Utc>>,
    pub rate_range: Option<ForecastRange>,
    pub chart: ChartSeries,
}

pub struct ForecastEngine;

impl ForecastEngine {
    pub fn calculate(samples: &[RateLimit], now: DateTime<Utc>) -> ForecastReport {
        let cycle = current_weekly_cycle(samples);
        let cleaned = remove_discontinuities(cycle);

        if !has_minimum_history(&cleaned) {
            return collecting_report(observed_points(&cleaned));
        }

        let first = cleaned.first().expect("minimum history checked");
        let latest = cleaned.last().expect("minimum history checked");
        let cycle_rate = endpoint_rate(first, latest).unwrap_or_default();
        let recent = recent_tail(&cleaned);
        let recent_rate = recent
            .first()
            .zip(recent.last())
            .and_then(|(first, last)| endpoint_rate(first, last));
        let recent_span_hours = span_hours(&recent);
        let recent_weight = if has_minimum_history(&recent) {
            (recent_span_hours / RECENT_HOURS as f64 * MAX_RECENT_WEIGHT)
                .clamp(0.0, MAX_RECENT_WEIGHT)
        } else {
            0.0
        };
        let consumed_per_day = recent_rate
            .map(|rate| cycle_rate * (1.0 - recent_weight) + rate * recent_weight)
            .unwrap_or(cycle_rate);
        let days_remaining = latest
            .resets_at
            .signed_duration_since(now)
            .num_seconds()
            .max(0) as f64
            / SECONDS_PER_DAY;
        let sustainable_per_day = if days_remaining > 0.0 {
            latest.remaining_percent / days_remaining
        } else {
            0.0
        };
        let estimated_depletion_at = if consumed_per_day >= MINIMUM_RATE {
            let seconds =
                (latest.remaining_percent / consumed_per_day * SECONDS_PER_DAY).round() as i64;
            Some(latest.observed_at + chrono::Duration::seconds(seconds))
        } else {
            None
        };

        ForecastReport {
            status: ForecastStatus::Estimated,
            confidence: ForecastConfidence::Low,
            consumed_per_day: Some(consumed_per_day),
            sustainable_per_day: Some(sustainable_per_day),
            pace_difference: Some(consumed_per_day - sustainable_per_day),
            estimated_depletion_at,
            rate_range: None,
            chart: ChartSeries {
                observed: observed_points(&cleaned),
                ..ChartSeries::default()
            },
        }
    }
}

fn collecting_report(observed: Vec<ChartPoint>) -> ForecastReport {
    ForecastReport {
        status: ForecastStatus::CollectingHistory,
        confidence: ForecastConfidence::Collecting,
        consumed_per_day: None,
        sustainable_per_day: None,
        pace_difference: None,
        estimated_depletion_at: None,
        rate_range: None,
        chart: ChartSeries {
            observed,
            ..ChartSeries::default()
        },
    }
}

fn current_weekly_cycle(samples: &[RateLimit]) -> Vec<&RateLimit> {
    let Some(latest) = samples
        .iter()
        .filter(|sample| sample.kind == LimitKind::Weekly)
        .max_by_key(|sample| sample.observed_at)
    else {
        return Vec::new();
    };

    let mut cycle: Vec<_> = samples
        .iter()
        .filter(|sample| sample.kind == LimitKind::Weekly)
        .filter(|sample| (sample.resets_at - latest.resets_at).num_seconds().abs() <= 5 * 60)
        .collect();
    cycle.sort_by_key(|sample| sample.observed_at);
    cycle
}

fn remove_discontinuities(samples: Vec<&RateLimit>) -> Vec<&RateLimit> {
    let mut cleaned = Vec::with_capacity(samples.len());
    for sample in samples {
        if cleaned.last().is_some_and(|previous: &&RateLimit| {
            sample.remaining_percent - previous.remaining_percent > DISCONTINUITY_POINTS
        }) {
            continue;
        }
        cleaned.push(sample);
    }
    cleaned
}

fn recent_tail<'a>(samples: &[&'a RateLimit]) -> Vec<&'a RateLimit> {
    let Some(latest) = samples.last() else {
        return Vec::new();
    };
    let cutoff = latest.observed_at - chrono::Duration::hours(RECENT_HOURS);
    let mut tail = Vec::new();

    for sample in samples.iter().rev().copied() {
        if sample.observed_at < cutoff {
            break;
        }
        if tail.last().is_some_and(|newer: &&RateLimit| {
            newer
                .observed_at
                .signed_duration_since(sample.observed_at)
                .num_seconds()
                > MAX_RECENT_GAP_HOURS * 3600
        }) {
            break;
        }
        tail.push(sample);
    }
    tail.reverse();
    tail
}

fn endpoint_rate(first: &RateLimit, last: &RateLimit) -> Option<f64> {
    let elapsed_days = last
        .observed_at
        .signed_duration_since(first.observed_at)
        .num_seconds() as f64
        / SECONDS_PER_DAY;
    (elapsed_days > 0.0)
        .then(|| ((first.remaining_percent - last.remaining_percent) / elapsed_days).max(0.0))
}

fn has_minimum_history(samples: &[&RateLimit]) -> bool {
    samples.len() >= MINIMUM_SAMPLES
        && samples
            .first()
            .zip(samples.last())
            .is_some_and(|(first, last)| {
                last.observed_at
                    .signed_duration_since(first.observed_at)
                    .num_minutes()
                    >= MINIMUM_SPAN_MINUTES
            })
}

fn span_hours(samples: &[&RateLimit]) -> f64 {
    samples
        .first()
        .zip(samples.last())
        .map(|(first, last)| {
            last.observed_at
                .signed_duration_since(first.observed_at)
                .num_seconds() as f64
                / 3600.0
        })
        .unwrap_or_default()
}

fn observed_points(samples: &[&RateLimit]) -> Vec<ChartPoint> {
    samples
        .iter()
        .map(|sample| ChartPoint {
            at: sample.observed_at,
            remaining_percent: sample.remaining_percent,
        })
        .collect()
}
