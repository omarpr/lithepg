import { useState } from "react";
import {
  Button,
  Tooltip,
} from "@mui/material";
import AccountTreeRoundedIcon from "@mui/icons-material/AccountTreeRounded";
import ArrowForwardRoundedIcon from "@mui/icons-material/ArrowForwardRounded";
import AutoAwesomeRoundedIcon from "@mui/icons-material/AutoAwesomeRounded";
import CheckRoundedIcon from "@mui/icons-material/CheckRounded";
import ContentCopyRoundedIcon from "@mui/icons-material/ContentCopyRounded";
import GitHubIcon from "@mui/icons-material/GitHub";
import OpenInNewRoundedIcon from "@mui/icons-material/OpenInNewRounded";
import QueryStatsRoundedIcon from "@mui/icons-material/QueryStatsRounded";
import StorageRoundedIcon from "@mui/icons-material/StorageRounded";
import TableChartRoundedIcon from "@mui/icons-material/TableChartRounded";
import TerminalRoundedIcon from "@mui/icons-material/TerminalRounded";

const installCommand = "brew install --cask omarpr/tap/lithepg";
const repositoryURL = "https://github.com/omarpr/lithepg";
const sourceTagsURL = `${repositoryURL}/tags`;

function CopyInstallButton({ compact = false }) {
  const [state, setState] = useState("idle");

  async function copyInstallCommand() {
    try {
      await navigator.clipboard.writeText(installCommand);
      setState("copied");
      window.setTimeout(() => setState("idle"), 1800);
    } catch {
      setState("select");
    }
  }

  const copied = state === "copied";
  const label = copied ? "Copied" : state === "select" ? "Select command" : "Copy";

  return (
    <Tooltip title={copied ? "Copied to clipboard" : "Copy install command"}>
      <Button
        className={`copy-button${copied ? " copied" : ""}${compact ? " compact" : ""}`}
        type="button"
        onClick={copyInstallCommand}
        aria-label="Copy Homebrew install command"
        startIcon={copied ? <CheckRoundedIcon /> : <ContentCopyRoundedIcon />}
      >
        {label}
      </Button>
    </Tooltip>
  );
}

function InstallCommand({ hero = false }) {
  return (
    <div className={hero ? "hero-install" : "install-command"}>
      {hero && (
        <div className="hero-install-heading">
          <span>Install the latest release</span>
        </div>
      )}
      <div className="command-row">
        <code><span>$</span> {installCommand}</code>
        <CopyInstallButton compact={hero} />
      </div>
      {hero && (
        <p className="hero-install-note">
          The tap pins every published build by version and SHA-256.
        </p>
      )}
    </div>
  );
}

function ProductPreview() {
  return (
    <div className="product-stage">
      <div className="app-window">
        <img
          className="product-screenshot"
          src="/assets/lithepg-app-snapshot.png"
          alt="LithePG showing its connection navigator, schema browser, SQL editor and query results"
        />
      </div>
      <div className="stage-shadow" aria-hidden="true" />
    </div>
  );
}

const features = [
  {
    number: "01",
    title: "Connections that stay organized",
    copy: "Move between databases from the left navigator and keep every password in the macOS Keychain.",
    icon: <StorageRoundedIcon />,
  },
  {
    number: "02",
    title: "Query without friction",
    copy: "Syntax highlighting, renameable tabs, history, cancellation and keyboard-first execution.",
    icon: <TerminalRoundedIcon />,
  },
  {
    number: "03",
    title: "Ask locally, review always",
    copy: "Draft schema-aware SQL with Apple's on-device model when available and a safe local fallback. The draft never runs automatically.",
    icon: <AutoAwesomeRoundedIcon />,
  },
  {
    number: "04",
    title: "See how data connects",
    copy: "Navigate schema metadata, inspect foreign keys and open a pan-and-zoom relationship graph.",
    icon: <AccountTreeRoundedIcon />,
  },
  {
    number: "05",
    title: "Results built for reuse",
    copy: "Copy cells or rows, inspect long values and export CSV, TSV, JSON, Markdown or SQL inserts.",
    icon: <TableChartRoundedIcon />,
  },
  {
    number: "06",
    title: "Understand the plan",
    copy: "Run EXPLAIN or EXPLAIN ANALYZE and scan a readable plan tree with cost shares, timings and the costliest node highlighted.",
    icon: <QueryStatsRoundedIcon />,
  },
];

function App() {
  return (
    <>
      <a className="skip-link" href="#main">Skip to content</a>

      <header className="site-header">
        <a className="brand" href="#top" aria-label="LithePG home">
          <img src="/assets/lithepg-icon.png" alt="" width="42" height="42" />
          <span>LithePG</span>
        </a>
        <nav aria-label="Primary navigation">
          <a href="#install">Install</a>
          <a href="#features">Features</a>
          <a href="#privacy">Local-first</a>
        </nav>
        <Button
          className="header-github"
          component="a"
          href={repositoryURL}
          rel="noreferrer"
          startIcon={<GitHubIcon />}
        >
          <span>GitHub</span>
        </Button>
      </header>

      <main id="main">
        <section className="hero" id="top">
          <div className="hero-glow" aria-hidden="true" />
          <div className="hero-copy">
            <div className="eyebrow"><span className="eyebrow-dot" />Native for macOS · Open source</div>
            <h1>
              <span className="hero-title-line">Postgres,</span>
              <span className="hero-title-line hero-title-accent">without the weight.</span>
            </h1>
            <p className="hero-lede">
              A fast, focused PostgreSQL client with a thoughtful query workflow,
              secure saved connections and local-first SQL drafting.
            </p>
            <InstallCommand hero />
            <div className="hero-actions">
              <Button
                className="button button-primary"
                component="a"
                href={sourceTagsURL}
                endIcon={<ArrowForwardRoundedIcon />}
              >
                Latest source tag
              </Button>
              <Button className="button button-secondary" component="a" href={repositoryURL} rel="noreferrer">
                View source
              </Button>
            </div>
            <p className="hero-meta">Open source · MIT licensed · macOS 14+</p>
          </div>
          <ProductPreview />
        </section>

        <section className="signal-strip" aria-label="Product qualities">
          <span><b>Pure Swift</b> native performance</span>
          <span><b>postgres-nio</b> no libpq</span>
          <span><b>Keychain</b> secrets stay secure</span>
          <span><b>Local-first</b> no cloud AI</span>
        </section>

        <section className="section features" id="features">
          <div className="section-heading">
            <div><p className="kicker">A complete daily driver</p><h2>Everything close.<br />Nothing in the way.</h2></div>
            <p>LithePG keeps the essentials within one native workspace, from the first connection test to the final exported result.</p>
          </div>
          <div className="feature-grid">
            {features.map((feature) => (
              <article className="feature-card" key={feature.number}>
                <div className="feature-icon">{feature.icon}</div>
                <span className="feature-number">{feature.number}</span>
                <h3>{feature.title}</h3>
                <p>{feature.copy}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="privacy-section" id="privacy">
          <div className="privacy-orbit" aria-hidden="true"><i /><i /><i /></div>
          <div className="privacy-copy">
            <p className="kicker">Local means local</p>
            <h2>Your database is not<br />training material.</h2>
            <p>
              LithePG does not send prompts, schemas, credentials, query history or results to a cloud AI service.
              Saved passwords live in Keychain. Generated SQL stays on your Mac until you decide to run it.
            </p>
            <a href={`${repositoryURL}#local-first-ai-in-plain-language`} rel="noreferrer">
              Read the privacy posture <OpenInNewRoundedIcon aria-hidden="true" />
            </a>
          </div>
          <div className="privacy-list">
            <div><span>01</span><p><strong>No cloud AI calls</strong><small>Drafting happens on-device.</small></p></div>
            <div><span>02</span><p><strong>Credentials in Keychain</strong><small>Passwords never enter saved JSON.</small></p></div>
            <div><span>03</span><p><strong>SQL never auto-runs</strong><small>You inspect every generated draft.</small></p></div>
            <div><span>04</span><p><strong>Open source</strong><small>Audit the behavior on GitHub.</small></p></div>
          </div>
        </section>

        <section className="section install-section" id="install">
          <div className="install-heading">
            <p className="kicker">Install LithePG</p>
            <h2>One command.<br />Always the latest.</h2>
            <p>
              Homebrew Cask is the default for clean installs and future updates.
              One command pulls the latest published build straight from the tap.
            </p>
          </div>
          <div className="install-panel">
            <div className="install-tabs">
              <span className="active">Homebrew</span>
              <span>macOS 14+</span>
            </div>
            <InstallCommand />
            <p className="availability-note is-live"><span />Live on the tap. Prefer to build it yourself? The latest tagged source is below.</p>
            <div className="source-install">
              <div><strong>Build the latest tagged source</strong><small>Requires macOS 14+ and Xcode / Swift 6.2.</small></div>
              <pre><code>{`git clone https://github.com/omarpr/lithepg.git\ncd lithepg\ngit checkout "$(git describe --tags --abbrev=0)"\n./script/rebuild_and_install.sh`}</code></pre>
            </div>
          </div>
        </section>

        <section className="final-cta">
          <img src="/assets/lithepg-icon.png" alt="LithePG app icon" width="112" height="112" />
          <p className="kicker">Built in the open</p>
          <h2>A focused Postgres client<br />with nothing to hide.</h2>
          <p>Read the code, open an issue or help shape what comes next.</p>
          <Button
            className="button button-light"
            component="a"
            href={repositoryURL}
            rel="noreferrer"
            endIcon={<OpenInNewRoundedIcon />}
          >
            omarpr/lithepg on GitHub
          </Button>
        </section>
      </main>

      <footer>
        <a className="brand footer-brand" href="#top">
          <img src="/assets/lithepg-icon.png" alt="" width="34" height="34" />
          <span>LithePG</span>
        </a>
        <p>Lean PostgreSQL for macOS.</p>
        <div>
          <a href={sourceTagsURL}>Source tags</a>
          <a href={repositoryURL} rel="noreferrer">GitHub</a>
          <a href={`${repositoryURL}/blob/main/LICENSE`} rel="noreferrer">MIT License</a>
          <span>© 2026 LithePG</span>
        </div>
      </footer>
    </>
  );
}

export default App;
