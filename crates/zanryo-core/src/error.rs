#[derive(Debug, thiserror::Error)]
pub enum ZanryoError {
    #[error("remaining percentage must be between 0 and 100, got {0}")]
    InvalidPercentage(f64),
    #[error("weekly Codex limit is missing")]
    MissingWeeklyLimit,
    #[error("protocol error: {0}")]
    Protocol(String),
    #[error("transport error: {0}")]
    Transport(String),
    #[error("storage error: {0}")]
    Storage(String),
}

pub type Result<T> = std::result::Result<T, ZanryoError>;
