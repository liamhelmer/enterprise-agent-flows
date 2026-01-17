//! IPC server using Unix domain sockets

use crate::error::DaemonResult;
use crate::queue::MergeQueue;
use crate::state::StateManager;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tracing::{debug, error, info, warn};

/// IPC server for handling client requests
pub struct IpcServer {
    socket_path: PathBuf,
    queue: MergeQueue,
    #[allow(dead_code)]
    state_manager: StateManager,
}

/// Request types from clients
#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Request {
    /// Register a new agent
    Register { agent_id: String },

    /// Enqueue a branch for merging
    Enqueue {
        agent_id: String,
        session_id: String,
        branch: String,
        worktree: String,
        target_branch: String,
    },

    /// Remove an agent from the queue
    Dequeue { agent_id: String },

    /// Get queue status
    Status,

    /// Get conflicts for an agent
    Conflicts { agent_id: String },

    /// Retry a failed merge
    Retry { agent_id: String },

    /// Wait for merge result (blocking)
    Wait { agent_id: String },

    /// End a session
    SessionEnd { session_id: String },

    /// Shutdown the daemon
    Shutdown,
}

/// Response to clients
#[derive(Debug, Serialize)]
#[serde(untagged)]
pub enum Response {
    Ok {
        status: &'static str,
    },
    Position {
        status: &'static str,
        position: usize,
    },
    Status {
        queue_length: usize,
        pending: usize,
        processing: usize,
        agents: Vec<String>,
    },
    Conflicts {
        files: Vec<String>,
    },
    MergeResult {
        result: String,
        details: Option<String>,
    },
    Error {
        status: &'static str,
        error: String,
    },
}

impl IpcServer {
    /// Create a new IPC server
    pub fn new(
        socket_path: PathBuf,
        queue: MergeQueue,
        state_manager: StateManager,
    ) -> DaemonResult<Self> {
        Ok(Self {
            socket_path,
            queue,
            state_manager,
        })
    }

    /// Run the IPC server
    pub async fn run(&self) -> DaemonResult<()> {
        let listener = UnixListener::bind(&self.socket_path)?;
        info!("IPC server listening on {:?}", self.socket_path);

        loop {
            match listener.accept().await {
                Ok((stream, _)) => {
                    let queue = self.queue.clone();
                    tokio::spawn(async move {
                        if let Err(e) = handle_connection(stream, queue).await {
                            error!("Connection error: {}", e);
                        }
                    });
                }
                Err(e) => {
                    warn!("Accept error: {}", e);
                }
            }
        }
    }
}

/// Handle a single client connection
async fn handle_connection(stream: UnixStream, queue: MergeQueue) -> DaemonResult<()> {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut line = String::new();

    while reader.read_line(&mut line).await? > 0 {
        debug!("Received: {}", line.trim());

        let response = match serde_json::from_str::<Request>(&line) {
            Ok(request) => process_request(request, &queue).await,
            Err(e) => Response::Error {
                status: "ERROR",
                error: format!("Invalid request: {}", e),
            },
        };

        let response_json = serde_json::to_string(&response)?;
        writer.write_all(response_json.as_bytes()).await?;
        writer.write_all(b"\n").await?;
        writer.flush().await?;

        line.clear();
    }

    Ok(())
}

/// Process a single request
async fn process_request(request: Request, queue: &MergeQueue) -> Response {
    match request {
        Request::Register { agent_id } => {
            debug!("Registered agent: {}", agent_id);
            Response::Ok { status: "OK" }
        }

        Request::Enqueue {
            agent_id,
            session_id,
            branch,
            worktree,
            target_branch,
        } => {
            match queue
                .enqueue(
                    agent_id,
                    session_id,
                    branch,
                    PathBuf::from(worktree),
                    target_branch,
                )
                .await
            {
                Ok(position) => Response::Position {
                    status: "OK",
                    position,
                },
                Err(e) => Response::Error {
                    status: "ERROR",
                    error: e.to_string(),
                },
            }
        }

        Request::Dequeue { agent_id } => match queue.dequeue(&agent_id).await {
            Ok(_) => Response::Ok { status: "OK" },
            Err(e) => Response::Error {
                status: "ERROR",
                error: e.to_string(),
            },
        },

        Request::Status => {
            let status = queue.status().await;
            Response::Status {
                queue_length: status.length,
                pending: status.pending,
                processing: status.processing,
                agents: status.agents,
            }
        }

        Request::Conflicts { agent_id } => match queue.get_conflicts(&agent_id).await {
            Ok(files) => Response::Conflicts { files },
            Err(e) => Response::Error {
                status: "ERROR",
                error: e.to_string(),
            },
        },

        Request::Retry { agent_id } => match queue.retry(&agent_id).await {
            Ok(position) => Response::Position {
                status: "OK",
                position,
            },
            Err(e) => Response::Error {
                status: "ERROR",
                error: e.to_string(),
            },
        },

        Request::Wait { agent_id: _ } => {
            // TODO: Implement blocking wait for merge result
            Response::MergeResult {
                result: "PENDING".to_string(),
                details: Some("Waiting not yet implemented".to_string()),
            }
        }

        Request::SessionEnd { session_id } => {
            debug!("Session ended: {}", session_id);
            Response::Ok { status: "OK" }
        }

        Request::Shutdown => {
            info!("Shutdown requested via IPC");
            queue.shutdown().await;
            Response::Ok { status: "OK" }
        }
    }
}
