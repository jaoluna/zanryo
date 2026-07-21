use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration as StdDuration;

use async_trait::async_trait;
use chrono::{Duration, TimeZone, Utc};
use tempfile::tempdir;
use zanryo_core::{
    AccountContext, ForecastStatus, Freshness, HistoryRepository, LimitKind, PlanType,
    QuotaService, RateLimit, RateLimitSource, Result, ZanryoError,
};

struct FakeSource {
    limits: Vec<RateLimit>,
    fail: bool,
    plan: PlanType,
    account_fail: bool,
    delay: StdDuration,
    reads: Arc<AtomicUsize>,
    account_reads: Arc<AtomicUsize>,
}

impl FakeSource {
    fn succeeding(limits: Vec<RateLimit>) -> Self {
        Self {
            limits,
            fail: false,
            plan: PlanType::Plus,
            account_fail: false,
            delay: StdDuration::ZERO,
            reads: Arc::new(AtomicUsize::new(0)),
            account_reads: Arc::new(AtomicUsize::new(0)),
        }
    }

    fn failing() -> Self {
        Self {
            limits: Vec::new(),
            fail: true,
            plan: PlanType::Unknown,
            account_fail: true,
            delay: StdDuration::ZERO,
            reads: Arc::new(AtomicUsize::new(0)),
            account_reads: Arc::new(AtomicUsize::new(0)),
        }
    }
}

#[async_trait]
impl RateLimitSource for FakeSource {
    async fn read_rate_limits(&self) -> Result<Vec<RateLimit>> {
        self.reads.fetch_add(1, Ordering::SeqCst);
        tokio::time::sleep(self.delay).await;

        if self.fail {
            Err(ZanryoError::Transport("source unavailable".to_owned()))
        } else {
            Ok(self.limits.clone())
        }
    }

    async fn read_account_plan(&self) -> Result<PlanType> {
        self.account_reads.fetch_add(1, Ordering::SeqCst);
        tokio::time::sleep(self.delay).await;

        if self.account_fail {
            Err(ZanryoError::Transport("account unavailable".to_owned()))
        } else {
            Ok(self.plan)
        }
    }
}

fn sample_limits() -> Vec<RateLimit> {
    let observed = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
    let reset = observed + Duration::days(5);
    vec![
        RateLimit::new(LimitKind::Weekly, "codex", 15.0, reset, observed).unwrap(),
        RateLimit::new(LimitKind::Spark, "codex_bengalfox", 72.0, reset, observed).unwrap(),
    ]
}

#[tokio::test]
async fn successful_refresh_is_fresh_and_persisted() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let service = QuotaService::new(FakeSource::succeeding(sample_limits()), history.clone());

    let snapshot = service.refresh().await.unwrap();

    assert_eq!(snapshot.freshness, Freshness::Fresh);
    assert!(snapshot.spark.is_some());
    assert_eq!(history.latest_limits().unwrap(), sample_limits());
}

#[tokio::test]
async fn failed_refresh_returns_existing_history_as_stale() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    history.insert_limits(&sample_limits()).unwrap();
    let service = QuotaService::new(FakeSource::failing(), history);

    let snapshot = service.refresh().await.unwrap();

    assert_eq!(snapshot.freshness, Freshness::Stale);
    assert_eq!(snapshot.weekly.remaining_percent, 15.0);
}

#[tokio::test]
async fn failed_refresh_without_history_returns_source_error() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let service = QuotaService::new(FakeSource::failing(), history);

    let error = service.refresh().await.unwrap_err();

    assert!(matches!(error, ZanryoError::Transport(_)));
}

#[tokio::test]
async fn concurrent_refreshes_share_one_source_read() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let mut source = FakeSource::succeeding(sample_limits());
    source.delay = StdDuration::from_millis(30);
    let reads = Arc::clone(&source.reads);
    let service = QuotaService::new(source, history);

    let (first, second) = tokio::join!(service.refresh(), service.refresh());

    assert_eq!(first.unwrap().freshness, Freshness::Fresh);
    assert_eq!(second.unwrap().freshness, Freshness::Fresh);
    assert_eq!(reads.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn forecast_uses_persisted_weekly_history() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
    let reset = now + Duration::days(5);
    let samples = vec![
        RateLimit::new(
            LimitKind::Weekly,
            "codex",
            80.0,
            reset,
            now - Duration::hours(2),
        )
        .unwrap(),
        RateLimit::new(
            LimitKind::Weekly,
            "codex",
            78.0,
            reset,
            now - Duration::hours(1),
        )
        .unwrap(),
        RateLimit::new(LimitKind::Weekly, "codex", 76.0, reset, now).unwrap(),
    ];
    history.insert_limits(&samples).unwrap();
    let service = QuotaService::new(FakeSource::succeeding(sample_limits()), history);

    let report = service.forecast(now).await.unwrap();

    assert_eq!(report.status, ForecastStatus::Estimated);
    assert!(report.consumed_per_day.is_some());
}

#[tokio::test]
async fn refresh_dashboard_returns_matching_quota_and_forecast() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let source = FakeSource::succeeding(sample_limits());
    let service = QuotaService::new(source, history);
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();

    let dashboard = service.refresh_dashboard(now).await.unwrap();

    assert_eq!(dashboard.quota.freshness, Freshness::Fresh);
    assert_eq!(
        dashboard.quota.weekly.remaining_percent,
        dashboard
            .forecast
            .chart
            .observed
            .last()
            .unwrap()
            .remaining_percent
    );
}

#[tokio::test]
async fn fresh_dashboard_includes_and_persists_the_account_plan() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let service = QuotaService::new(FakeSource::succeeding(sample_limits()), history.clone());
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();

    let dashboard = service.refresh_dashboard(now).await.unwrap();

    assert_eq!(dashboard.account.plan_type, PlanType::Plus);
    assert_eq!(
        history.latest_account_context().unwrap(),
        Some(AccountContext::new(PlanType::Plus, now))
    );
}

#[tokio::test]
async fn fresh_dashboard_reuses_a_plan_cached_less_than_24_hours_ago() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
    history
        .upsert_account_context(&AccountContext::new(
            PlanType::Plus,
            now - Duration::hours(23),
        ))
        .unwrap();
    let source = FakeSource::succeeding(sample_limits());
    let account_reads = Arc::clone(&source.account_reads);
    let service = QuotaService::new(source, history);

    let dashboard = service.refresh_dashboard(now).await.unwrap();

    assert_eq!(dashboard.account.plan_type, PlanType::Plus);
    assert_eq!(account_reads.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn failed_account_read_keeps_the_fresh_quota_and_cached_plan() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
    history
        .upsert_account_context(&AccountContext::new(
            PlanType::Plus,
            now - Duration::hours(24),
        ))
        .unwrap();
    let mut source = FakeSource::succeeding(sample_limits());
    source.account_fail = true;
    let account_reads = Arc::clone(&source.account_reads);
    let service = QuotaService::new(source, history);

    let dashboard = service.refresh_dashboard(now).await.unwrap();

    assert_eq!(dashboard.quota.freshness, Freshness::Fresh);
    assert_eq!(dashboard.account.plan_type, PlanType::Plus);
    assert_eq!(account_reads.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn concurrent_fresh_dashboards_share_one_account_read() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let mut source = FakeSource::succeeding(sample_limits());
    source.delay = StdDuration::from_millis(30);
    let account_reads = Arc::clone(&source.account_reads);
    let service = QuotaService::new(source, history);
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();

    let (first, second) = tokio::join!(
        service.refresh_dashboard(now),
        service.refresh_dashboard(now)
    );

    assert_eq!(first.unwrap().account.plan_type, PlanType::Plus);
    assert_eq!(second.unwrap().account.plan_type, PlanType::Plus);
    assert_eq!(account_reads.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn concurrent_account_rpc_failure_without_cache_shares_one_unknown_outcome() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let mut source = FakeSource::succeeding(sample_limits());
    source.account_fail = true;
    source.delay = StdDuration::from_millis(30);
    let account_reads = Arc::clone(&source.account_reads);
    let service = QuotaService::new(source, history);
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();

    let (first, second) = tokio::join!(
        service.refresh_dashboard(now),
        service.refresh_dashboard(now)
    );

    assert_eq!(first.unwrap().account, AccountContext::unknown());
    assert_eq!(second.unwrap().account, AccountContext::unknown());
    assert_eq!(account_reads.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn concurrent_account_rpc_failure_shares_the_cached_plan_outcome() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
    history
        .upsert_account_context(&AccountContext::new(
            PlanType::Plus,
            now - Duration::hours(24),
        ))
        .unwrap();
    let mut source = FakeSource::succeeding(sample_limits());
    source.account_fail = true;
    source.delay = StdDuration::from_millis(30);
    let account_reads = Arc::clone(&source.account_reads);
    let service = QuotaService::new(source, history);

    let (first, second) = tokio::join!(
        service.refresh_dashboard(now),
        service.refresh_dashboard(now)
    );

    assert_eq!(first.unwrap().account.plan_type, PlanType::Plus);
    assert_eq!(second.unwrap().account.plan_type, PlanType::Plus);
    assert_eq!(account_reads.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn sequential_account_rpc_failures_retry_after_a_shared_outcome() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let mut source = FakeSource::succeeding(sample_limits());
    source.account_fail = true;
    let account_reads = Arc::clone(&source.account_reads);
    let service = QuotaService::new(source, history);
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();

    let first = service.refresh_dashboard(now).await.unwrap();
    let second = service.refresh_dashboard(now).await.unwrap();

    assert_eq!(first.account, AccountContext::unknown());
    assert_eq!(second.account, AccountContext::unknown());
    assert_eq!(account_reads.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn stale_dashboard_does_not_read_the_account_plan() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    history.insert_limits(&sample_limits()).unwrap();
    let source = FakeSource::failing();
    let account_reads = Arc::clone(&source.account_reads);
    let service = QuotaService::new(source, history);
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();

    let dashboard = service.refresh_dashboard(now).await.unwrap();

    assert_eq!(dashboard.quota.freshness, Freshness::Stale);
    assert_eq!(dashboard.account, AccountContext::unknown());
    assert_eq!(account_reads.load(Ordering::SeqCst), 0);
}
