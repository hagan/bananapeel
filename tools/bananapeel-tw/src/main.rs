mod scanner;
mod record;
mod hashing;

use clap::{Parser, Subcommand};
use anyhow::Result;

#[derive(Parser, Debug)]
#[command(name = "bananapeel-tw", version, about = "Bananapeel Tripwire-like scanner (prototype)")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Initialize baseline (JSON Lines)
    Init {
        /// Root directory to scan
        #[arg(long, default_value = "/")]
        root: String,
        /// Output baseline file (JSONL)
        #[arg(long, default_value = "baseline.jsonl")]
        out: String,
        /// Exclude patterns (repeatable)
        #[arg(long)]
        exclude: Vec<String>,
    },
    /// Check filesystem against baseline
    Check {
        #[arg(long, default_value = "/")]
        root: String,
        #[arg(long)]
        baseline: String,
        #[arg(long, default_value = "report.json")]
        out: String,
        #[arg(long)]
        exclude: Vec<String>,
    },
    /// Print a report (human-readable)
    Print {
        #[arg(long)]
        report: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { root, out, exclude } => {
            scanner::init_baseline(&root, &out, &exclude)?;
        }
        Commands::Check { root, baseline, out, exclude } => {
            scanner::check_against_baseline(&root, &baseline, &out, &exclude)?;
        }
        Commands::Print { report } => {
            scanner::print_report(&report)?;
        }
    }
    Ok( )
}
