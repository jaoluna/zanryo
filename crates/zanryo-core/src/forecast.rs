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
const WEEKLY_CYCLE_DAYS: i64 = 7;

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
        if samples.first().is_some_and(|first| {
            samples
                .iter()
                .any(|sample| sample.provider != first.provider)
        }) {
            return collecting_report(Vec::new());
        }

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
        let elapsed_since_latest_days = now
            .signed_duration_since(latest.observed_at)
            .num_seconds()
            .max(0) as f64
            / SECONDS_PER_DAY;
        let current_remaining_percent = (latest.remaining_percent
            - consumed_per_day * elapsed_since_latest_days)
            .clamp(0.0, 100.0);
        let days_remaining = latest
            .resets_at
            .signed_duration_since(now)
            .num_seconds()
            .max(0) as f64
            / SECONDS_PER_DAY;
        let sustainable_per_day = if days_remaining > 0.0 {
            current_remaining_percent / days_remaining
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
        let total_span_hours = span_hours(&cleaned);
        let residuals: Vec<f64> = cleaned
            .iter()
            .map(|sample| {
                let days_before_latest = latest
                    .observed_at
                    .signed_duration_since(sample.observed_at)
                    .num_seconds() as f64
                    / SECONDS_PER_DAY;
                let predicted = latest.remaining_percent + consumed_per_day * days_before_latest;
                (sample.remaining_percent - predicted).abs()
            })
            .collect();
        let mean_absolute_residual = residuals.iter().sum::<f64>() / residuals.len() as f64;
        let rate_margin = (mean_absolute_residual / (total_span_hours / 24.0).max(0.25))
            .max(consumed_per_day * 0.10)
            .max(0.25);
        let rate_range = ForecastRange {
            low: (consumed_per_day - rate_margin).max(0.0),
            high: consumed_per_day + rate_margin,
        };
        let relative_margin = rate_margin / consumed_per_day.max(MINIMUM_RATE);
        let confidence =
            if cleaned.len() >= 20 && total_span_hours >= 24.0 && relative_margin <= 0.25 {
                ForecastConfidence::High
            } else if cleaned.len() >= 6 && total_span_hours >= 6.0 && relative_margin <= 0.60 {
                ForecastConfidence::Medium
            } else {
                ForecastConfidence::Low
            };
        let chart = build_chart(
            &cleaned,
            now,
            latest.resets_at,
            current_remaining_percent,
            consumed_per_day,
            &rate_range,
        );

        ForecastReport {
            status: ForecastStatus::Estimated,
            confidence,
            consumed_per_day: Some(consumed_per_day),
            sustainable_per_day: Some(sustainable_per_day),
            pace_difference: Some(consumed_per_day - sustainable_per_day),
            estimated_depletion_at,
            rate_range: Some(rate_range),
            chart,
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

fn chart_observed_points(samples: &[&RateLimit], budget_start: DateTime<Utc>) -> Vec<ChartPoint> {
    let visible_samples: Vec<_> = samples
        .iter()
        .copied()
        .filter(|sample| sample.observed_at >= budget_start)
        .collect();

    let mut points = vec![ChartPoint {
        at: budget_start,
        remaining_percent: 100.0,
    }];

    let Some(first) = visible_samples.first() else {
        return points;
    };

    push_observed_point(&mut points, first);

    for window in visible_samples.windows(2) {
        let previous = window[0];
        let current = window[1];
        if (current.remaining_percent - previous.remaining_percent).abs() < f64::EPSILON {
            continue;
        }

        if points
            .last()
            .is_none_or(|point| point.at != previous.observed_at)
        {
            push_observed_point(&mut points, previous);
        }

        push_observed_point(&mut points, current);
    }

    let latest = visible_samples.last().expect("first checked");
    if points
        .last()
        .is_none_or(|point| point.at != latest.observed_at)
    {
        push_observed_point(&mut points, latest);
    }

    points
}

fn push_observed_point(points: &mut Vec<ChartPoint>, sample: &RateLimit) {
    if let Some(last) = points.last_mut() {
        if last.at == sample.observed_at {
            last.remaining_percent = sample.remaining_percent;
            return;
        }
    }

    points.push(ChartPoint {
        at: sample.observed_at,
        remaining_percent: sample.remaining_percent,
    });
}

fn build_chart(
    samples: &[&RateLimit],
    now: DateTime<Utc>,
    reset: DateTime<Utc>,
    current_remaining_percent: f64,
    rate: f64,
    rate_range: &ForecastRange,
) -> ChartSeries {
    let budget_start = reset - chrono::Duration::days(WEEKLY_CYCLE_DAYS);
    let forecast_end = forecast_end(now, reset, current_remaining_percent, rate);
    let observed = chart_observed_points(samples, budget_start);
    let forecast = projection_times(now, forecast_end)
        .into_iter()
        .map(|at| {
            let days = at.signed_duration_since(now).num_seconds().max(0) as f64 / SECONDS_PER_DAY;
            let remaining = (current_remaining_percent - rate * days).clamp(0.0, 100.0);
            let optimistic = (current_remaining_percent - rate_range.low * days).clamp(0.0, 100.0);
            let pessimistic =
                (current_remaining_percent - rate_range.high * days).clamp(0.0, 100.0);
            ForecastPoint {
                at,
                remaining_percent: remaining,
                uncertainty: ForecastRange {
                    low: pessimistic.min(remaining),
                    high: optimistic.max(remaining),
                },
            }
        })
        .collect();
    let sustainable = vec![
        ChartPoint {
            at: budget_start,
            remaining_percent: 100.0,
        },
        ChartPoint {
            at: reset,
            remaining_percent: 0.0,
        },
    ];

    ChartSeries {
        observed,
        forecast,
        sustainable,
    }
}

fn forecast_end(
    now: DateTime<Utc>,
    reset: DateTime<Utc>,
    current_remaining_percent: f64,
    rate: f64,
) -> DateTime<Utc> {
    if rate < MINIMUM_RATE || current_remaining_percent <= 0.0 {
        return reset;
    }

    let seconds_to_zero = (current_remaining_percent / rate * SECONDS_PER_DAY).round() as i64;
    let depletion = now + chrono::Duration::seconds(seconds_to_zero);
    depletion.min(reset)
}

fn projection_times(now: DateTime<Utc>, reset: DateTime<Utc>) -> Vec<DateTime<Utc>> {
    if reset <= now {
        return vec![now];
    }

    let total_seconds = reset.signed_duration_since(now).num_seconds();
    (0..=24)
        .map(|step| now + chrono::Duration::seconds(total_seconds * i64::from(step) / 24))
        .collect()
}
