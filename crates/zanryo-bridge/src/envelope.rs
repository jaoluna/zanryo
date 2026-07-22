use serde::Serialize;
use zanryo_core::ZanryoError;

pub const SCHEMA_VERSION: u16 = 1;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct BridgeError {
    pub code: &'static str,
    pub message: String,
}

impl BridgeError {
    pub fn invalid_handle() -> Self {
        Self {
            code: "invalid_handle",
            message: "Zanryo bridge handle is invalid".to_owned(),
        }
    }

    pub fn internal(message: impl Into<String>) -> Self {
        Self {
            code: "internal_error",
            message: message.into(),
        }
    }
}

impl From<ZanryoError> for BridgeError {
    fn from(error: ZanryoError) -> Self {
        let code = match &error {
            ZanryoError::Storage(_) => "storage_error",
            ZanryoError::Transport(_) => "codex_unavailable",
            ZanryoError::Protocol(_)
            | ZanryoError::InvalidPercentage(_)
            | ZanryoError::MissingWeeklyLimit => "protocol_error",
        };

        Self {
            code,
            message: error.to_string(),
        }
    }
}

#[derive(Debug, Serialize)]
pub struct BridgeEnvelope<T>
where
    T: Serialize,
{
    pub schema_version: u16,
    pub ok: bool,
    pub data: Option<T>,
    pub error: Option<BridgeError>,
}

pub fn success<T>(data: T) -> BridgeEnvelope<T>
where
    T: Serialize,
{
    BridgeEnvelope {
        schema_version: SCHEMA_VERSION,
        ok: true,
        data: Some(data),
        error: None,
    }
}

pub fn failure(error: BridgeError) -> BridgeEnvelope<()> {
    BridgeEnvelope {
        schema_version: SCHEMA_VERSION,
        ok: false,
        data: None,
        error: Some(error),
    }
}
