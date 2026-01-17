//! Git merge operations

use crate::config::{Config, MergeStrategy};
use crate::queue::{MergeResult, QueueEntry};
use git2::{Commit, Index, MergeOptions, Repository, Signature};
use std::path::PathBuf;
use tracing::{debug, info};

/// Handles git merge operations
pub struct Merger {
    repo_path: PathBuf,
    config: Config,
}

impl Merger {
    /// Create a new merger
    pub fn new(repo_path: PathBuf, config: Config) -> Self {
        Self { repo_path, config }
    }

    /// Perform a merge operation
    pub async fn merge(&self, entry: &QueueEntry) -> Result<MergeResult, git2::Error> {
        let repo = Repository::open(&self.repo_path)?;

        // Get the target branch
        let target_ref = repo.find_branch(&entry.target_branch, git2::BranchType::Local)?;
        let target_commit = target_ref.get().peel_to_commit()?;

        // Get the agent branch
        let agent_ref = repo.find_branch(&entry.branch, git2::BranchType::Local)?;
        let agent_commit = agent_ref.get().peel_to_commit()?;

        debug!(
            "Merging {} ({}) into {} ({})",
            entry.branch,
            agent_commit.id(),
            entry.target_branch,
            target_commit.id()
        );

        // Checkout target branch
        repo.set_head(&format!("refs/heads/{}", entry.target_branch))?;
        repo.checkout_head(Some(git2::build::CheckoutBuilder::default().force()))?;

        // Perform merge based on strategy
        match self.config.merge_strategy {
            MergeStrategy::Merge => self.do_merge(&repo, &target_commit, &agent_commit, entry),
            MergeStrategy::Rebase => self.do_rebase(&repo, &target_commit, &agent_commit, entry),
            MergeStrategy::Squash => self.do_squash(&repo, &target_commit, &agent_commit, entry),
        }
    }

    /// Perform a standard merge
    fn do_merge(
        &self,
        repo: &Repository,
        target: &Commit,
        agent: &Commit,
        entry: &QueueEntry,
    ) -> Result<MergeResult, git2::Error> {
        let mut opts = MergeOptions::new();
        opts.fail_on_conflict(false);

        // Perform the merge analysis
        let annotated = repo.find_annotated_commit(agent.id())?;
        let (analysis, _) = repo.merge_analysis(&[&annotated])?;

        if analysis.is_up_to_date() {
            info!("Branch {} is already up to date", entry.branch);
            return Ok(MergeResult::Success {
                commit_sha: target.id().to_string(),
            });
        }

        if analysis.is_fast_forward() {
            // Fast-forward merge
            let refname = format!("refs/heads/{}", entry.target_branch);
            repo.reference(&refname, agent.id(), true, "fast-forward merge")?;

            return Ok(MergeResult::Success {
                commit_sha: agent.id().to_string(),
            });
        }

        // Regular merge
        repo.merge(&[&annotated], Some(&mut opts), None)?;

        // Check for conflicts
        let mut index = repo.index()?;
        if index.has_conflicts() {
            let conflicts = self.get_conflict_files(&index)?;

            // Clean up the merge state
            repo.cleanup_state()?;

            return Ok(MergeResult::Conflict { files: conflicts });
        }

        // Commit the merge
        let tree_id = index.write_tree()?;
        let tree = repo.find_tree(tree_id)?;

        let sig = self.default_signature()?;
        let message = format!("Merge agent {} into {}", entry.agent_id, entry.target_branch);

        let commit_id = repo.commit(
            Some("HEAD"),
            &sig,
            &sig,
            &message,
            &tree,
            &[target, agent],
        )?;

        // Cleanup merge state
        repo.cleanup_state()?;

        Ok(MergeResult::Success {
            commit_sha: commit_id.to_string(),
        })
    }

    /// Perform a rebase merge
    fn do_rebase(
        &self,
        repo: &Repository,
        target: &Commit,
        agent: &Commit,
        _entry: &QueueEntry,
    ) -> Result<MergeResult, git2::Error> {
        // For rebase, we replay agent commits on top of target
        // This is a simplified version - full rebase would handle multiple commits

        let annotated_target = repo.find_annotated_commit(target.id())?;
        let annotated_agent = repo.find_annotated_commit(agent.id())?;

        let mut rebase = repo.rebase(
            Some(&annotated_agent),
            Some(&annotated_target),
            None,
            None,
        )?;

        let sig = self.default_signature()?;

        while let Some(op) = rebase.next() {
            match op {
                Ok(_) => {
                    // Check for conflicts
                    let index = repo.index()?;
                    if index.has_conflicts() {
                        let conflicts = self.get_conflict_files(&index)?;
                        rebase.abort()?;
                        return Ok(MergeResult::Conflict { files: conflicts });
                    }

                    // Commit this step
                    if let Err(e) = rebase.commit(None, &sig, None) {
                        rebase.abort()?;
                        return Ok(MergeResult::Failed {
                            error: format!("Rebase commit failed: {}", e),
                        });
                    }
                }
                Err(e) => {
                    rebase.abort()?;
                    return Ok(MergeResult::Failed {
                        error: format!("Rebase step failed: {}", e),
                    });
                }
            }
        }

        // Finish the rebase
        rebase.finish(Some(&sig))?;

        // Get the final commit
        let head = repo.head()?.peel_to_commit()?;

        Ok(MergeResult::Success {
            commit_sha: head.id().to_string(),
        })
    }

    /// Perform a squash merge
    fn do_squash(
        &self,
        repo: &Repository,
        target: &Commit,
        agent: &Commit,
        entry: &QueueEntry,
    ) -> Result<MergeResult, git2::Error> {
        // For squash, we merge but create a single commit with all changes
        let annotated = repo.find_annotated_commit(agent.id())?;

        let mut opts = MergeOptions::new();
        opts.fail_on_conflict(false);

        repo.merge(&[&annotated], Some(&mut opts), None)?;

        // Check for conflicts
        let mut index = repo.index()?;
        if index.has_conflicts() {
            let conflicts = self.get_conflict_files(&index)?;
            repo.cleanup_state()?;
            return Ok(MergeResult::Conflict { files: conflicts });
        }

        // Create a single squash commit
        let tree_id = index.write_tree()?;
        let tree = repo.find_tree(tree_id)?;

        let sig = self.default_signature()?;
        let message = format!(
            "Squash merge agent {} into {}\n\nOriginal commits from: {}",
            entry.agent_id, entry.target_branch, entry.branch
        );

        // Note: squash merge only has one parent (target)
        let commit_id = repo.commit(Some("HEAD"), &sig, &sig, &message, &tree, &[target])?;

        repo.cleanup_state()?;

        Ok(MergeResult::Success {
            commit_sha: commit_id.to_string(),
        })
    }

    /// Get list of conflicting files
    fn get_conflict_files(&self, index: &Index) -> Result<Vec<String>, git2::Error> {
        let mut conflicts = Vec::new();

        for conflict in index.conflicts()? {
            let conflict = conflict?;

            // Get the path from any of the conflict entries
            if let Some(entry) = conflict.our.or(conflict.their).or(conflict.ancestor) {
                if let Some(path) = std::str::from_utf8(&entry.path).ok() {
                    conflicts.push(path.to_string());
                }
            }
        }

        Ok(conflicts)
    }

    /// Get default signature for commits
    fn default_signature(&self) -> Result<Signature<'static>, git2::Error> {
        Signature::now("Agent Fork-Join", "agent-fork-join@localhost")
    }
}
