use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::{LimitKind, RateLimit};

const MINIMUM_SAMPLES: usize = 3;
const MINIMUM_SPAN_MINUTES: i64 = 30;

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
    pub fn calculate(samples: &[RateLimit], _now: DateTime<Utc>) -> ForecastReport {
        let cleaned = current_weekly_cycle(samples);
        let observed = cleaned
            .iter()
            .map(|sample| ChartPoint {
                at: sample.observed_at,
                remaining_percent: sample.remaining_percent,
            })
            .collect();
        let span_minutes = cleaned
            .first()
            .zip(cleaned.last())
            .map(|(first, last)| {
                last.observed_at
                    .signed_duration_since(first.observed_at)
                    .num_minutes()
            })
            .unwrap_or_default();

        if cleaned.len() < MINIMUM_SAMPLES || span_minutes < MINIMUM_SPAN_MINUTES {
            return collecting_report(observed);
        }

        collecting_report(observed)
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
