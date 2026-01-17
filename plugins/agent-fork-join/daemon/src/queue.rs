//! FIFO merge queue implementation

use crate::config::Config;
use crate::error::{DaemonError, DaemonResult};
use crate::merger::Merger;
use crate::state::StateManager;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::{Mutex, Notify};
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// Entry in the merge queue
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueueEntry {
    /// Unique entry ID
    pub id: Uuid,

    /// Agent ID that owns this entry
    pub agent_id: String,

    /// Session ID this agent belongs to
    pub session_id: String,

    /// Branch to merge
    pub branch: String,

    /// Path to the agent's worktree
    pub worktree: PathBuf,

    /// Target branch to merge into
    pub target_branch: String,

    /// Number of merge attempts
    pub attempts: u32,

    /// When this entry was queued
    pub queued_at: DateTime<Utc>,

    /// Current status
    pub status: EntryStatus,

    /// Last error message (if any)
    pub last_error: Option<String>,

    /// Conflicting files (if status is Conflict)
    pub conflict_files: Vec<String>,
}

/// Status of a queue entry
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum EntryStatus {
    /// Waiting in queue
    Pending,
    /// Currently being merged
    Processing,
    /// Merge succeeded
    Merged,
    /// Merge failed with conflicts
    Conflict,
    /// Merge failed (non-conflict error)
    Failed,
    /// Cancelled by user
    Cancelled,
}

/// Result of a merge operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MergeResult {
    /// Merge succeeded
    Success { commit_sha: String },
    /// Merge has conflicts
    Conflict { files: Vec<String> },
    /// Merge failed for other reasons
    Failed { error: String },
}

/// FIFO merge queue
#[derive(Clone)]
pub struct MergeQueue {
    /// The queue itself
    queue: Arc<Mutex<VecDeque<QueueEntry>>>,

    /// Repository path
    repo_path: PathBuf,

    /// State manager for persistence
    state_manager: StateManager,

    /// Configuration
    config: Config,

    /// Notification when new entries are added
    notify: Arc<Notify>,

    /// Shutdown flag
    shutdown: Arc<Mutex<bool>>,

    /// Merger for git operations
    merger: Arc<Merger>,
}

impl MergeQueue {
    /// Create a new merge queue
    pub fn new(repo_path: PathBuf, state_manager: StateManager, config: Config) -> Self {
        let merger = Arc::new(Merger::new(repo_path.clone(), config.clone()));

        Self {
            queue: Arc::new(Mutex::new(VecDeque::new())),
            repo_path,
            state_manager,
            config,
            notify: Arc::new(Notify::new()),
            shutdown: Arc::new(Mutex::new(false)),
            merger,
        }
    }

    /// Recover pending entries from persistent state
    pub async fn recover(&self) -> DaemonResult<usize> {
        let entries = self.state_manager.load_pending_entries().await?;
        let count = entries.len();

        let mut queue = self.queue.lock().await;
        for entry in entries {
            if entry.status == EntryStatus::Pending || entry.status == EntryStatus::Processing {
                let mut recovered = entry;
                recovered.status = EntryStatus::Pending;
                queue.push_back(recovered);
            }
        }

        if count > 0 {
            self.notify.notify_one();
        }

        Ok(count)
    }

    /// Add an entry to the queue
    pub async fn enqueue(
        &self,
        agent_id: String,
        session_id: String,
        branch: String,
        worktree: PathBuf,
        target_branch: String,
    ) -> DaemonResult<usize> {
        let mut queue = self.queue.lock().await;

        // Check if queue is full
        if queue.len() >= self.config.max_queue_size {
            return Err(DaemonError::QueueFull(self.config.max_queue_size));
        }

        // Check if agent is already in queue
        if queue.iter().any(|e| e.agent_id == agent_id && e.status == EntryStatus::Pending) {
            return Err(DaemonError::AgentAlreadyQueued(agent_id));
        }

        let entry = QueueEntry {
            id: Uuid::new_v4(),
            agent_id,
            session_id,
            branch,
            worktree,
            target_branch,
            attempts: 0,
            queued_at: Utc::now(),
            status: EntryStatus::Pending,
            last_error: None,
            conflict_files: vec![],
        };

        // Persist the entry
        self.state_manager.save_entry(&entry).await?;

        let position = queue.len();
        queue.push_back(entry);

        // Notify the processing loop
        self.notify.notify_one();

        info!("Enqueued agent {} at position {}", queue.back().unwrap().agent_id, position);
        Ok(position)
    }

    /// Remove an entry from the queue
    pub async fn dequeue(&self, agent_id: &str) -> DaemonResult<Option<QueueEntry>> {
        let mut queue = self.queue.lock().await;

        if let Some(pos) = queue.iter().position(|e| e.agent_id == agent_id) {
            let entry = queue.remove(pos).unwrap();
            self.state_manager.delete_entry(&entry.id).await?;
            Ok(Some(entry))
        } else {
            Ok(None)
        }
    }

    /// Re-queue an entry (after conflict resolution)
    pub async fn retry(&self, agent_id: &str) -> DaemonResult<usize> {
        let mut queue = self.queue.lock().await;

        if let Some(entry) = queue.iter_mut().find(|e| e.agent_id == agent_id) {
            if entry.attempts >= self.config.max_retries {
                return Err(DaemonError::MaxRetriesExceeded(agent_id.to_string()));
            }

            entry.status = EntryStatus::Pending;
            entry.conflict_files.clear();
            entry.last_error = None;

            self.state_manager.save_entry(entry).await?;
            self.notify.notify_one();

            Ok(queue.iter().position(|e| e.agent_id == agent_id).unwrap())
        } else {
            Err(DaemonError::AgentNotFound(agent_id.to_string()))
        }
    }

    /// Get queue status
    pub async fn status(&self) -> QueueStatus {
        let queue = self.queue.lock().await;

        QueueStatus {
            length: queue.len(),
            pending: queue.iter().filter(|e| e.status == EntryStatus::Pending).count(),
            processing: queue.iter().filter(|e| e.status == EntryStatus::Processing).count(),
            agents: queue.iter().map(|e| e.agent_id.clone()).collect(),
        }
    }

    /// Get conflicts for an agent
    pub async fn get_conflicts(&self, agent_id: &str) -> DaemonResult<Vec<String>> {
        let queue = self.queue.lock().await;

        if let Some(entry) = queue.iter().find(|e| e.agent_id == agent_id) {
            Ok(entry.conflict_files.clone())
        } else {
            Err(DaemonError::AgentNotFound(agent_id.to_string()))
        }
    }

    /// Main processing loop
    pub async fn process_loop(&self) {
        loop {
            // Check for shutdown
            if *self.shutdown.lock().await {
                info!("Processing loop shutting down");
                break;
            }

            // Wait for notification or timeout
            tokio::select! {
                _ = self.notify.notified() => {},
                _ = tokio::time::sleep(tokio::time::Duration::from_secs(1)) => {},
            }

            // Process the next pending entry
            if let Err(e) = self.process_next().await {
                error!("Error processing queue entry: {}", e);
            }
        }
    }

    /// Process the next pending entry
    async fn process_next(&self) -> DaemonResult<()> {
        // Get the next pending entry
        let entry = {
            let mut queue = self.queue.lock().await;

            if let Some(entry) = queue.iter_mut().find(|e| e.status == EntryStatus::Pending) {
                entry.status = EntryStatus::Processing;
                entry.attempts += 1;
                self.state_manager.save_entry(entry).await?;
                Some(entry.clone())
            } else {
                None
            }
        };

        let Some(entry) = entry else {
            return Ok(());
        };

        info!(
            "Processing merge for agent {} (attempt {})",
            entry.agent_id, entry.attempts
        );

        // Perform the merge
        let result = self.merger.merge(&entry).await;

        // Update entry based on result
        {
            let mut queue = self.queue.lock().await;

            if let Some(e) = queue.iter_mut().find(|e| e.id == entry.id) {
                match result {
                    Ok(MergeResult::Success { commit_sha }) => {
                        info!("Merge succeeded for agent {}: {}", e.agent_id, commit_sha);
                        e.status = EntryStatus::Merged;
                    }
                    Ok(MergeResult::Conflict { files }) => {
                        warn!("Merge conflict for agent {}: {:?}", e.agent_id, files);
                        e.status = EntryStatus::Conflict;
                        e.conflict_files = files;
                    }
                    Ok(MergeResult::Failed { error }) => {
                        error!("Merge failed for agent {}: {}", e.agent_id, error);
                        e.status = EntryStatus::Failed;
                        e.last_error = Some(error);
                    }
                    Err(err) => {
                        error!("Merge error for agent {}: {}", e.agent_id, err);
                        e.status = EntryStatus::Failed;
                        e.last_error = Some(err.to_string());
                    }
                }

                self.state_manager.save_entry(e).await?;
            }
        }

        Ok(())
    }

    /// Shutdown the queue gracefully
    pub async fn shutdown(&self) {
        *self.shutdown.lock().await = true;
        self.notify.notify_waiters();
        debug!("Queue shutdown initiated");
    }
}

/// Queue status summary
#[derive(Debug, Serialize, Deserialize)]
pub struct QueueStatus {
    pub length: usize,
    pub pending: usize,
    pub processing: usize,
    pub agents: Vec<String>,
}
