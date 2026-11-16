import { useEffect, useState } from "react";
import {
  Button,
  Tooltip,
} from "@mui/material";
import AccountTreeRoundedIcon from "@mui/icons-material/AccountTreeRounded";
import ArrowForwardRoundedIcon from "@mui/icons-material/ArrowForwardRounded";
import AutoAwesomeRoundedIcon from "@mui/icons-material/AutoAwesomeRounded";
import CheckRoundedIcon from "@mui/icons-material/CheckRounded";
import DarkModeRoundedIcon from "@mui/icons-material/DarkModeRounded";
import ContentCopyRoundedIcon from "@mui/icons-material/ContentCopyRounded";
import GitHubIcon from "@mui/icons-material/GitHub";
import LightModeRoundedIcon from "@mui/icons-material/LightModeRounded";
import OpenInNewRoundedIcon from "@mui/icons-material/OpenInNewRounded";
import QueryStatsRoundedIcon from "@mui/icons-material/QueryStatsRounded";
import StorageRoundedIcon from "@mui/icons-material/StorageRounded";
import TableChartRoundedIcon from "@mui/icons-material/TableChartRounded";
import TerminalRoundedIcon from "@mui/icons-material/TerminalRounded";

const installCommand = "brew install --cask omarpr/tap/lithepg";
const repositoryURL = "https://github.com/omarpr/lithepg";
const sourceTagsURL = `${repositoryURL}/tags`;
const changelogURL = `${repositoryURL}/blob/main/CHANGELOG.md`;

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

const themeStorageKey = "lithepg-theme";

// Dark is the default. public/theme-init.js applies a saved light choice before
// the first paint; this button flips it and remembers the choice.
function ThemeToggle() {
  // Start dark to match the prerendered markup, then read the real theme.
  const [theme, setTheme] = useState("dark");

  useEffect(() => {
    setTheme(document.documentElement.dataset.theme === "light" ? "light" : "dark");
  }, []);

  function toggleTheme() {
    const next = theme === "light" ? "dark" : "light";
    if (next === "light") {
      document.documentElement.dataset.theme = "light";
    } else {
      delete document.documentElement.dataset.theme;
    }
    try {
      if (next === "light") {
        localStorage.setItem(themeStorageKey, "light");
      } else {
        localStorage.removeItem(themeStorageKey);
      }
    } catch {
      // Storage can be blocked; the choice then lasts for this visit only.
    }
    setTheme(next);
  }

  const label = theme === "light" ? "Switch to dark mode" : "Switch to light mode";
  return (
    <Tooltip title={label}>
      <button className="theme-toggle" type="button" onClick={toggleTheme} aria-label={label}>
        {theme === "light" ? <DarkModeRoundedIcon /> : <LightModeRoundedIcon />}
      </button>
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
          width="3248"
          height="1934"
          fetchPriority="high"
          alt="LithePG with a query on the customers table, its results with accented names and the schema browser"
        />
      </div>
      <div className="stage-shadow" aria-hidden="true" />
    </div>
  );
}

const features = [
  {
    title: "Connections that stay organized",
    copy: "Find any database from a filterable sidebar, import your Neon projects with one scan and reach private hosts through an SSH tunnel. TLS to remote hosts is verified by default, passwords stay in the macOS Keychain and a dropped connection comes back with one click.",
    icon: <StorageRoundedIcon />,
  },
  {
    title: "Query without friction",
    copy: "Autocomplete for keywords, tables and columns as you type. Run the statement under the cursor straight from a longer script, with highlighting, tabs, history and keyboard shortcuts you can make your own.",
    icon: <TerminalRoundedIcon />,
  },
  {
    title: "Ask locally, review always",
    copy: "Describe what you need in plain English and get schema-aware SQL from Apple's on-device model on Macs with Apple Intelligence. The draft never runs automatically.",
    icon: <AutoAwesomeRoundedIcon />,
  },
  {
    title: "See how data connects",
    copy: "Navigate schema metadata, inspect foreign keys and open a pan-and-zoom relationship graph.",
    icon: <AccountTreeRoundedIcon />,
  },
  {
    title: "Results built for reuse",
    copy: "Filter rows across every page, format JSON in the cell editor, copy cells or rows and export CSV, TSV, JSON, Markdown or SQL inserts. Big queries stop on the server at 10,000 rows instead of downloading everything.",
    icon: <TableChartRoundedIcon />,
  },
  {
    title: "Understand the plan",
    copy: "Run EXPLAIN or EXPLAIN ANALYZE and scan a readable plan tree with cost shares, timings and the costliest node highlighted.",
    icon: <QueryStatsRoundedIcon />,
  },
];

const faqs = [
  {
    question: "Is LithePG free?",
    answer: "Yes. LithePG is free and open source under the MIT license. There is no account, no subscription and no telemetry.",
  },
  {
    question: "Which Macs does it run on?",
    answer: "Macs with Apple silicon running macOS 14 Sonoma or later. Ask in English also needs macOS 26 with Apple Intelligence turned on.",
  },
  {
    question: "Does LithePG send my data anywhere?",
    answer: "No. Prompts, schema details, query results and passwords stay on your Mac. LithePG connects only to the databases you add and, when you ask it to scan, runs the Neon CLI you installed.",
  },
  {
    question: "Which PostgreSQL databases can it connect to?",
    answer: "Local servers and hosted ones such as Neon, over plain TCP, verified TLS or an SSH tunnel through a bastion host.",
  },
  {
    question: "How do I update it?",
    answer: "Run brew upgrade --cask lithepg. Every release is listed in the changelog on GitHub.",
  },
];

const faqStructuredData = JSON.stringify({
  "@context": "https://schema.org",
  "@type": "FAQPage",
  mainEntity: faqs.map(({ question, answer }) => ({
    "@type": "Question",
    name: question,
    acceptedAnswer: { "@type": "Answer", text: answer },
  })),
});

function App() {
  return (
    <>
      <a className="skip-link" href="#main">Skip to content</a>

      <header className="site-header">
        <a className="brand" href="#top" aria-label="LithePG home">
          <img src="/apple-touch-icon.png" alt="" width="42" height="42" />
          <span>LithePG</span>
        </a>
        <nav aria-label="Primary navigation">
          <a href="#install">Install</a>
          <a href="#features">Features</a>
          <a href="#privacy">Local-first</a>
          <a href="#faq">FAQ</a>
        </nav>
        <div className="header-actions">
          <ThemeToggle />
          <Button
            className="header-github"
            component="a"
            href={repositoryURL}
            rel="noreferrer"
            startIcon={<GitHubIcon />}
          >
            <span>GitHub</span>
          </Button>
        </div>
      </header>

      <main id="main">
        <section className="hero" id="top">
          <div className="hero-glow" aria-hidden="true" />
          <div className="hero-copy">
            <div className="eyebrow"><span className="eyebrow-dot" />PostgreSQL client for Mac</div>
            <h1>
              <span className="hero-title-line">Postgres,</span>
              <span className="hero-title-line hero-title-accent">without the weight.</span>
            </h1>
            <p className="hero-lede">
              LithePG is a free, open source PostgreSQL client built in Swift for macOS.
              Write SQL with autocomplete, browse your schema, read query plans and export
              results, with AI drafting that never leaves your Mac.
            </p>
            <InstallCommand hero />
            <div className="hero-actions">
              <Button
                className="button button-primary"
                component="a"
                href={changelogURL}
                rel="noreferrer"
                endIcon={<ArrowForwardRoundedIcon />}
              >
                What is new
              </Button>
              <Button className="button button-secondary" component="a" href={repositoryURL} rel="noreferrer">
                View source
              </Button>
            </div>
            <p className="hero-meta">Free · MIT licensed · Apple silicon · macOS 14+</p>
          </div>
          <ProductPreview />
        </section>

        <section className="signal-strip" aria-label="Product qualities">
          <span><b>Under 7 MB</b> download</span>
          <span><b>Swift and SwiftUI</b> no Electron</span>
          <span><b>Keychain</b> for saved passwords</span>
          <span><b>On-device AI</b> no cloud calls</span>
        </section>

        <section className="section features" id="features">
          <div className="section-heading">
            <div><p className="kicker">Features</p><h2>Connect, query,<br />inspect, export.</h2></div>
            <p>The work you do in a database every day, in one native Mac window that opens fast and stays out of your way.</p>
          </div>
          <div className="feature-grid">
            {features.map((feature) => (
              <article className="feature-card" key={feature.title}>
                <div className="feature-icon">{feature.icon}</div>
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
            <h2>Your database is not training material.</h2>
            <p>
              LithePG does not send prompts, schemas, credentials, query history or results to a cloud AI service.
              Saved passwords live in Keychain. Generated SQL stays on your Mac until you decide to run it.
            </p>
            <a href={`${repositoryURL}#local-first-ai-in-plain-language`} rel="noreferrer">
              How LithePG handles your data <OpenInNewRoundedIcon aria-hidden="true" />
            </a>
          </div>
          <div className="privacy-list">
            <div><p><strong>No cloud AI calls</strong><small>Drafting runs on Apple's on-device model.</small></p></div>
            <div><p><strong>Passwords in Keychain</strong><small>Never written to the saved connection files.</small></p></div>
            <div><p><strong>SQL never runs on its own</strong><small>Every draft lands in the editor for you to read.</small></p></div>
            <div><p><strong>No telemetry</strong><small>The source is on GitHub if you want to check.</small></p></div>
          </div>
        </section>

        <section className="section install-section" id="install">
          <div className="install-heading">
            <p className="kicker">Install</p>
            <h2>Install with<br />Homebrew.</h2>
            <p>
              The cask installs the signed and notarized app. When a new version
              comes out, <code>brew upgrade --cask lithepg</code> brings it in.
            </p>
          </div>
          <div className="install-panel">
            <div className="install-tabs">
              <span className="active">Homebrew cask</span>
              <span>Apple silicon · macOS 14+</span>
            </div>
            <InstallCommand />
            <p className="availability-note">Prefer to build it yourself? The latest tagged source works too.</p>
            <div className="source-install">
              <div><strong>Build the latest tagged source</strong><small>Requires macOS 14+ and Xcode with Swift 6.4 or newer.</small></div>
              <pre><code>{`git clone https://github.com/omarpr/lithepg.git\ncd lithepg\ngit checkout "$(git describe --tags --abbrev=0)"\n./script/rebuild_and_install.sh`}</code></pre>
            </div>
          </div>
        </section>

        <section className="section faq-section" id="faq">
          <div className="faq-heading">
            <p className="kicker">Questions</p>
            <h2>Good to know.</h2>
          </div>
          <div className="faq-list">
            {faqs.map((faq) => (
              <details key={faq.question}>
                <summary>{faq.question}</summary>
                <p>{faq.answer}</p>
              </details>
            ))}
          </div>
          <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: faqStructuredData }} />
        </section>

        <section className="final-cta">
          <img src="/assets/lithepg-icon.png" alt="LithePG app icon" width="112" height="112" loading="lazy" />
          <p className="kicker">Built in the open</p>
          <h2>Read the code.<br />Shape what comes next.</h2>
          <p>Open an issue, suggest a feature or send a pull request.</p>
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
          <img src="/apple-touch-icon.png" alt="" width="34" height="34" loading="lazy" />
          <span>LithePG</span>
        </a>
        <p>Lean PostgreSQL for macOS.</p>
        <div>
          <a href={changelogURL} rel="noreferrer">Changelog</a>
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
