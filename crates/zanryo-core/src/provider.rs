use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ProviderId {
    #[serde(rename = "openai")]
    OpenAi,
    #[serde(rename = "claude")]
    Claude,
}

impl ProviderId {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::OpenAi => "openai",
            Self::Claude => "claude",
        }
    }
}
