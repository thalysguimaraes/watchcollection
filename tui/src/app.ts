import {
  render,
  Box,
  Text,
  Spacer,
  createSignal,
  useInput,
  useApp,
  createTextInput,
  renderTextInput,
  useTerminalSize,
  useScroll,
  Scroll,
  type VNode,
} from 'tuiuiu.js';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const CRAWLER_DIR = path.join(REPO_ROOT, 'crawler');
const OUTPUT_DIR = path.join(CRAWLER_DIR, 'output_watchcharts');
const API_DIR = path.join(REPO_ROOT, 'api');
const DEPLOY_STATE_PATH = path.join(REPO_ROOT, 'tui', '.deploy_state.json');
const CATALOG_BUNDLE_PATH = path.join(API_DIR, 'data', 'catalog_bundle.json');
const RAILWAY_SERVICE = process.env.TUI_RAILWAY_SERVICE || 'watch-api';
const PYTHON_BIN = resolvePythonBin();

const DEFAULT_WATCHCHARTS_MODELS = Number(process.env.TUI_WATCHCHARTS_MODELS || 50);
const DEFAULT_CHRONO24_LISTINGS = Number(process.env.TUI_CHRONO24_LISTINGS || 40);
const DEFAULT_CHRONO24_MIN_LISTINGS = Number(process.env.TUI_CHRONO24_MIN_LISTINGS || 6);
const WATCHCHARTS_COOKIES_FILE = process.env.WATCHCHARTS_COOKIES_FILE || path.join(CRAWLER_DIR, 'watchcharts_cookies.txt');

const LOG_LIMIT = 200;
const LOG_VIEW_LINES = 9;
const BRAND_VIEW_LINES = 14;
const SIDE_PANEL_WIDTH = 32;
const BRAND_PANEL_WIDTH = 48;
const BRAND_CONTENT_WIDTH = BRAND_PANEL_WIDTH - 4;
const LOG_PANEL_PADDING = 2;
const SIDE_PANEL_PADDING = 4;

type Phase = 'watchcharts' | 'chrono24' | 'deploy';
type PhaseStatus = 'ready' | 'missing' | 'running' | 'error';

type BrandEntry = {
  slug: string;
  name: string;
  entryUrl?: string | null;
  watchchartsFile: string;
  chrono24File: string;
};

type JobState = {
  phase: Phase;
  brandSlug?: string;
  status: 'running' | 'success' | 'error';
};

type Mode = 'normal' | 'addUrl' | 'addSlug' | 'confirmDeploy';
type CatalogInfo = {
  version?: string;
  generatedAt?: string;
  brands?: number;
  models?: number;
};
type DeployState = {
  deployed_at?: string;
  status?: string;
  catalog_version?: string;
  catalog_generated_at?: string;
  error?: string;
};
type BrandStats = {
  total: number;
  market: number;
};

const [brands, setBrands] = createSignal<BrandEntry[]>([]);
const [selectedIndex, setSelectedIndex] = createSignal(0);
const [logLines, setLogLines] = createSignal<string[]>([]);
const [statusMessage, setStatusMessage] = createSignal('Ready');
const [activeJob, setActiveJob] = createSignal<JobState | null>(null);
const [mode, setMode] = createSignal<Mode>('normal');
const [pendingUrl, setPendingUrl] = createSignal('');
const [pendingSlug, setPendingSlug] = createSignal('');
const [lastErrors, setLastErrors] = createSignal<Record<string, string>>({});
const [catalogInfo, setCatalogInfo] = createSignal<CatalogInfo | null>(null);
const [deployState, setDeployState] = createSignal<DeployState | null>(null);
const [scrollTarget, setScrollTarget] = createSignal<'brands' | 'logs'>('brands');
const brandScroll = useScroll({ height: BRAND_VIEW_LINES });
const logScroll = useScroll({ height: LOG_VIEW_LINES });
const [brandStats, setBrandStats] = createSignal<Record<string, BrandStats>>({});

function appendLog(line: string) {
  setLogLines((prev) => {
    const next = [...prev, line];
    return next.length > LOG_LIMIT ? next.slice(next.length - LOG_LIMIT) : next;
  });
}

function resetLogs(title: string) {
  setLogLines([title]);
}

function resolvePythonBin(): string {
  const envPython = process.env.TUI_PYTHON_BIN;
  if (envPython) return envPython;
  const venvCandidates = [
    path.join(CRAWLER_DIR, 'venv', 'bin', 'python'),
    path.join(CRAWLER_DIR, '.venv', 'bin', 'python'),
  ];
  for (const candidate of venvCandidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return 'python3';
}

function normalizeName(value: string): string {
  const cleaned = value.replace(/[_-]+/g, ' ').trim();
  if (!cleaned) return value;
  return cleaned
    .split(' ')
    .map((part) => (part ? part[0].toUpperCase() + part.slice(1) : part))
    .join(' ');
}

function safeReadJson(filePath: string): Record<string, unknown> | null {
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function loadCatalogInfo(): CatalogInfo | null {
  if (!fs.existsSync(CATALOG_BUNDLE_PATH)) return null;
  const data = safeReadJson(CATALOG_BUNDLE_PATH);
  if (!data) return null;
  const brands = Array.isArray(data.brands) ? data.brands.length : 0;
  let models = 0;
  if (Array.isArray(data.brands)) {
    for (const brand of data.brands) {
      if (brand && Array.isArray((brand as any).models)) {
        models += (brand as any).models.length;
      }
    }
  }
  return {
    version: data.version as string | undefined,
    generatedAt: data.generated_at as string | undefined,
    brands,
    models,
  };
}

function loadDeployState(): DeployState | null {
  if (!fs.existsSync(DEPLOY_STATE_PATH)) return null;
  const data = safeReadJson(DEPLOY_STATE_PATH);
  return (data as DeployState) || null;
}

function saveDeployState(state: DeployState) {
  try {
    fs.writeFileSync(DEPLOY_STATE_PATH, JSON.stringify(state, null, 2));
  } catch {
    // ignore write errors
  }
  setDeployState(state);
}

function formatTimestamp(ts?: string): string {
  if (!ts) return 'n/a';
  const date = new Date(ts);
  if (Number.isNaN(date.getTime())) return ts;
  return date.toISOString().replace('T', ' ').replace('Z', '');
}

function listBrandFiles(): BrandEntry[] {
  if (!fs.existsSync(OUTPUT_DIR)) {
    return [];
  }
  const files = fs.readdirSync(OUTPUT_DIR).filter((file) => file.endsWith('.json'));
  const skipSuffixes = [
    '_chrono24.json',
    '_failed.json',
    '_failed_history.json',
    '_failed_downloads.json',
    '_checkpoint.json',
    '_listings.json',
    '_image_manifest.json',
    '_download_progress.json',
  ];

  const baseFiles = files.filter((file) => !skipSuffixes.some((suffix) => file.endsWith(suffix)));

  return baseFiles.map((file) => {
    const slug = file.replace('.json', '');
    const watchchartsFile = path.join(OUTPUT_DIR, file);
    const chrono24File = path.join(OUTPUT_DIR, `${slug}_chrono24.json`);
    const data = safeReadJson(watchchartsFile);
    const rawName = (data?.brand as string) || slug;
    const entryUrl = (data?.entry_url as string) || null;
    return {
      slug,
      name: normalizeName(rawName),
      entryUrl,
      watchchartsFile,
      chrono24File,
    };
  });
}

function refreshBrands() {
  const entries = listBrandFiles().sort((a, b) => a.name.localeCompare(b.name));
  setBrands(entries);
  const nextIndex = Math.min(Math.max(0, selectedIndex()), Math.max(0, entries.length - 1));
  setSelectedIndex(nextIndex);
  ensureSelectedVisible(entries, nextIndex);
  setCatalogInfo(loadCatalogInfo());
  setDeployState(loadDeployState());
  setBrandStats(buildBrandStats(entries));
}

function ensureSelectedVisible(list: BrandEntry[], index: number) {
  const total = list.length;
  if (!total) return;
  const top = brandScroll.scrollTop();
  if (index < top) {
    brandScroll.scrollTo(index);
    return;
  }
  if (index >= top + BRAND_VIEW_LINES) {
    brandScroll.scrollTo(index - BRAND_VIEW_LINES + 1);
  }
}

function phaseStatusFor(brand: BrandEntry, phase: Phase): PhaseStatus {
  const active = activeJob();
  if (active && active.status === 'running') {
    if (active.phase === phase && active.brandSlug === brand.slug) {
      return 'running';
    }
  }
  const errorKey = `${brand.slug}:${phase}`;
  const lastError = lastErrors()[errorKey];
  if (lastError) {
    return 'error';
  }
  if (phase === 'watchcharts') {
    return fs.existsSync(brand.watchchartsFile) ? 'ready' : 'missing';
  }
  if (phase === 'chrono24') {
    return fs.existsSync(brand.chrono24File) ? 'ready' : 'missing';
  }
  return 'missing';
}

function statusBadge(label: string, status: PhaseStatus): VNode {
  let color: string = 'gray';
  let symbol = '--';
  if (status === 'ready') {
    color = 'green';
    symbol = 'OK';
  } else if (status === 'running') {
    color = 'yellow';
    symbol = 'RUN';
  } else if (status === 'error') {
    color = 'red';
    symbol = 'ERR';
  }
  return Text({ color: color as any }, `${label}:${symbol}`);
}

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  if (max <= 3) return text.slice(0, max);
  return `${text.slice(0, max - 3)}...`;
}

function wrapLine(text: string, width: number): string[] {
  if (width <= 0) return [''];
  if (text.length <= width) return [text];
  const lines: string[] = [];
  let start = 0;
  while (start < text.length) {
    lines.push(text.slice(start, start + width));
    start += width;
  }
  return lines;
}

function wrapLines(lines: string[], width: number): string[] {
  const wrapped: string[] = [];
  lines.forEach((line) => {
    wrapped.push(...wrapLine(line, width));
  });
  return wrapped;
}

function summarizePhase(list: BrandEntry[], phase: Phase) {
  let ready = 0;
  let error = 0;
  let running = 0;
  let missing = 0;
  list.forEach((brand) => {
    const status = phaseStatusFor(brand, phase);
    if (status === 'ready') ready += 1;
    if (status === 'error') error += 1;
    if (status === 'running') running += 1;
    if (status === 'missing') missing += 1;
  });
  return { ready, error, running, missing };
}

function deriveSlugFromUrl(entryUrl: string): string {
  try {
    const url = new URL(entryUrl);
    const pathParts = url.pathname.split('/').filter(Boolean);
    const brandIndex = pathParts.findIndex((part) => part === 'brand' || part === 'brands' || part === 'watches');
    if (brandIndex >= 0 && pathParts[brandIndex + 1]) {
      return pathParts[brandIndex + 1].toLowerCase();
    }
    const brandParam = url.searchParams.get('brand') || url.searchParams.get('brandSlug') || url.searchParams.get('slug');
    if (brandParam) {
      return brandParam.toLowerCase();
    }
  } catch {
    return '';
  }
  return '';
}

function setError(brandSlug: string | undefined, phase: Phase, message: string) {
  if (!brandSlug) return;
  setLastErrors((prev) => ({ ...prev, [`${brandSlug}:${phase}`]: message }));
}

function clearError(brandSlug: string | undefined, phase: Phase) {
  if (!brandSlug) return;
  setLastErrors((prev) => {
    const next = { ...prev };
    delete next[`${brandSlug}:${phase}`];
    return next;
  });
}

function runCommand(command: string, args: string[], cwd: string, label: string): Promise<number> {
  return new Promise((resolve) => {
    const proc = spawn(command, args, { cwd, env: process.env });
    let stdoutBuffer = '';
    let stderrBuffer = '';

    const pushLines = (data: string, prefix: string) => {
      const lines = data.split(/\r?\n/);
      lines.forEach((line) => {
        if (line.trim().length > 0) {
          appendLog(`${prefix} ${line}`);
        }
      });
    };

    proc.stdout.on('data', (chunk) => {
      stdoutBuffer += chunk.toString();
      const parts = stdoutBuffer.split(/\r?\n/);
      stdoutBuffer = parts.pop() || '';
      parts.forEach((line) => pushLines(line, label));
    });

    proc.stderr.on('data', (chunk) => {
      stderrBuffer += chunk.toString();
      const parts = stderrBuffer.split(/\r?\n/);
      stderrBuffer = parts.pop() || '';
      parts.forEach((line) => pushLines(line, `${label} [err]`));
    });

    proc.on('close', (code) => {
      if (stdoutBuffer.trim().length > 0) {
        pushLines(stdoutBuffer, label);
      }
      if (stderrBuffer.trim().length > 0) {
        pushLines(stderrBuffer, `${label} [err]`);
      }
      resolve(code ?? 1);
    });
  });
}

async function runPhase(phase: Phase, brand?: BrandEntry): Promise<boolean> {
  if (activeJob()?.status === 'running') {
    setStatusMessage('A job is already running');
    return false;
  }

  if (phase !== 'deploy' && !brand) {
    setStatusMessage('Select a brand first');
    return false;
  }

  if (phase === 'watchcharts' && brand && !brand.entryUrl) {
    appendLog('Missing entry URL. Use Add Brand to provide the WatchCharts URL.');
    setStatusMessage('Missing entry URL for WatchCharts');
    setError(brand.slug, phase, 'missing entry url');
    return false;
  }

  setStatusMessage(`Running ${phase}...`);
  setActiveJob({ phase, brandSlug: brand?.slug, status: 'running' });
  if (brand) {
    clearError(brand.slug, phase);
  }

  let code = 1;

  if (phase === 'watchcharts' && brand) {
    resetLogs(`[watchcharts] ${brand.slug}`);
    const watchchartsArgs = [
      '-m',
      'watchcollection_crawler.pipelines.watchcharts',
      '--entry-url',
      brand.entryUrl || '',
      '--brand',
      brand.name,
      '--brand-slug',
      brand.slug,
      '--backend',
      'curl-impersonate',
      '--models',
      String(DEFAULT_WATCHCHARTS_MODELS),
    ];
    if (fs.existsSync(WATCHCHARTS_COOKIES_FILE)) {
      watchchartsArgs.push('--cookies-file', WATCHCHARTS_COOKIES_FILE);
    }
    code = await runCommand(PYTHON_BIN, watchchartsArgs, CRAWLER_DIR, '[watchcharts]');
  }

  if (phase === 'chrono24' && brand) {
    resetLogs(`[chrono24] ${brand.slug}`);
    code = await runCommand(
      PYTHON_BIN,
      [
        '-m',
        'watchcollection_crawler.pipelines.chrono24_market',
        '--brand',
        brand.slug,
        '--listings',
        String(DEFAULT_CHRONO24_LISTINGS),
        '--min-listings',
        String(DEFAULT_CHRONO24_MIN_LISTINGS),
      ],
      CRAWLER_DIR,
      '[chrono24]'
    );
  }

  if (phase === 'deploy') {
    resetLogs('[deploy] transform');
    const transformCode = await runCommand(
      PYTHON_BIN,
      ['-m', 'watchcollection_crawler.pipelines.transform'],
      CRAWLER_DIR,
      '[transform]'
    );
    if (transformCode === 0) {
      setCatalogInfo(loadCatalogInfo());
      appendLog('[deploy] running railway up');
      code = await runCommand('railway', ['up', '--service', RAILWAY_SERVICE], API_DIR, '[railway]');
      if (code === 0) {
        const catalog = loadCatalogInfo();
        saveDeployState({
          deployed_at: new Date().toISOString(),
          status: 'success',
          catalog_version: catalog?.version,
          catalog_generated_at: catalog?.generatedAt,
        });
      } else {
        saveDeployState({
          deployed_at: new Date().toISOString(),
          status: 'error',
          error: `railway up exit ${code}`,
        });
      }
    } else {
      code = transformCode;
      saveDeployState({
        deployed_at: new Date().toISOString(),
        status: 'error',
        error: `transform exit ${code}`,
      });
    }
  }

  const success = code === 0;
  setActiveJob({ phase, brandSlug: brand?.slug, status: success ? 'success' : 'error' });

  if (!success && brand) {
    setError(brand.slug, phase, `exit ${code}`);
  }

  refreshBrands();
  setStatusMessage(success ? `${phase} finished` : `${phase} failed (exit ${code})`);
  return success;
}

async function runNewBrandFlow(url: string, slug: string) {
  const brandName = normalizeName(slug);
  const brand: BrandEntry = {
    slug,
    name: brandName,
    entryUrl: url,
    watchchartsFile: path.join(OUTPUT_DIR, `${slug}.json`),
    chrono24File: path.join(OUTPUT_DIR, `${slug}_chrono24.json`),
  };

  const okWatchcharts = await runPhase('watchcharts', brand);
  if (!okWatchcharts) return;
  await runPhase('chrono24', brand);
}

function startAddBrand() {
  setPendingUrl('');
  setPendingSlug('');
  brandUrlInput.clear();
  brandSlugInput.clear();
  setMode('addUrl');
  setStatusMessage('Enter WatchCharts brand URL');
}

const brandUrlInput = createTextInput({
  placeholder: 'https://watchcharts.com/...',
  isActive: () => mode() === 'addUrl',
  onChange: (value) => setPendingUrl(value),
  onSubmit: () => {
    const url = pendingUrl().trim();
    if (!url) {
      setStatusMessage('URL cannot be empty');
      return;
    }
    const slug = deriveSlugFromUrl(url);
    setPendingSlug(slug);
    if (!slug) {
      brandSlugInput.setValue('');
      setMode('addSlug');
      setStatusMessage('Enter brand slug');
      return;
    }
    brandSlugInput.setValue(slug);
    setMode('addSlug');
    setStatusMessage('Confirm brand slug (Enter to continue)');
  },
  onCancel: () => {
    setMode('normal');
    setStatusMessage('Cancelled');
  },
});

const brandSlugInput = createTextInput({
  placeholder: 'brand-slug',
  isActive: () => mode() === 'addSlug',
  onChange: (value) => setPendingSlug(value),
  onSubmit: () => {
    const url = pendingUrl().trim();
    const slug = pendingSlug().trim().toLowerCase();
    if (!url || !slug) {
      setStatusMessage('URL and slug are required');
      return;
    }
    setMode('normal');
    setStatusMessage(`Starting brand flow: ${slug}`);
    void runNewBrandFlow(url, slug);
  },
  onCancel: () => {
    setMode('normal');
    setStatusMessage('Cancelled');
  },
});

function App() {
  const { exit } = useApp();
  const { columns } = useTerminalSize();

  useInput((char, key) => {
    if (mode() !== 'normal') return;

    const list = brands();
    const selected = list[selectedIndex()];

    if (scrollTarget() === 'logs') {
      if (key.upArrow || key.downArrow || char === 'j' || char === 'k' || char === 'u' || char === 'd' || char === 'g' || char === 'G') {
        return;
      }
    }

    if (key.upArrow) {
      const next = Math.max(0, selectedIndex() - 1);
      setSelectedIndex(next);
      ensureSelectedVisible(list, next);
      setScrollTarget('brands');
      return;
    }
    if (key.downArrow) {
      const next = Math.min(list.length - 1, selectedIndex() + 1);
      setSelectedIndex(next);
      ensureSelectedVisible(list, next);
      setScrollTarget('brands');
      return;
    }

    if (char === 'q' || key.escape) {
      exit();
      return;
    }

    if (char === 'r') {
      refreshBrands();
      setStatusMessage('Refreshed');
      return;
    }

    if (char === 'a') {
      startAddBrand();
      return;
    }

    if (char === 'w') {
      void runPhase('watchcharts', selected);
      return;
    }

    if (char === 'c') {
      void runPhase('chrono24', selected);
      return;
    }

    if (char === 'g') {
      setMode('confirmDeploy');
      setStatusMessage('Press y to deploy or n to cancel');
      return;
    }

    if (char === 'l') {
      const next = scrollTarget() === 'logs' ? 'brands' : 'logs';
      setScrollTarget(next);
      setStatusMessage(`Scroll focus: ${next}`);
      return;
    }

    if (scrollTarget() === 'brands') {
      if (char === 'j') {
        brandScroll.scrollBy(1);
        return;
      }
      if (char === 'k') {
        brandScroll.scrollBy(-1);
        return;
      }
    }

    if (mode() === 'confirmDeploy') {
      return;
    }
  });

  useInput((char) => {
    if (mode() !== 'confirmDeploy') return;
    if (char === 'y') {
      setMode('normal');
      void runPhase('deploy');
      return;
    }
    if (char === 'n' || char === 'q') {
      setMode('normal');
      setStatusMessage('Deploy cancelled');
    }
  });

  const list = brands();
  const selected = list[selectedIndex()];
  const watchSummary = summarizePhase(list, 'watchcharts');
  const chronoSummary = summarizePhase(list, 'chrono24');
  const catalog = catalogInfo();
  const deploy = deployState();
  const logWidth = Math.max(40, columns - 4);
  const logContentWidth = Math.max(20, logWidth - LOG_PANEL_PADDING);
  const sideContentWidth = Math.max(10, SIDE_PANEL_WIDTH - SIDE_PANEL_PADDING);
  const brandNameMax = Math.max(10, BRAND_CONTENT_WIDTH - 18);
  const stats = brandStats();

  const listRows = list.length
    ? list.map((brand, idx) => {
        const isSelected = idx === selectedIndex();
        const watchStatus = phaseStatusFor(brand, 'watchcharts');
        const chronoStatus = phaseStatusFor(brand, 'chrono24');
        const nameLabel = `${isSelected ? '>' : ' '} ${brand.name}`;
        const paddedName = truncate(nameLabel, brandNameMax).padEnd(brandNameMax, ' ');
        return Box(
          { flexDirection: 'row' },
          Text({ color: isSelected ? 'cyan' : 'white', bold: isSelected }, `${paddedName} `),
          statusBadge('W', watchStatus),
          Text({}, ' '),
          statusBadge('C', chronoStatus)
        );
      })
    : [Text({ color: 'gray' }, 'No brands found. Press a to add one.')];

  const hiddenLogs = Math.max(0, logLines().length - LOG_VIEW_LINES);
  const logDisplayLines = wrapLines(logLines(), logContentWidth);

  const detailPanel = selected
    ? [
        Text({ bold: true }, selected.name),
        Text({ color: 'gray' }, `slug: ${selected.slug}`),
        Text({ color: 'gray' }, `entry: ${selected.entryUrl || 'missing'}`),
        Text({}, ''),
        Text({ color: 'gray' }, 'Status:'),
        Box(
          { flexDirection: 'row' },
          statusBadge('W', phaseStatusFor(selected, 'watchcharts')),
          Text({}, ' '),
          statusBadge('C', phaseStatusFor(selected, 'chrono24'))
        ),
        Text({ color: 'gray' }, 'Coverage:'),
        Text(
          { color: 'gray' },
          `W: ${stats[selected.slug]?.total ?? 0}  C: ${stats[selected.slug]?.market ?? 0}`
        ),
      ]
    : [Text({ color: 'gray' }, 'Select a brand')];

  const shortcutsPanel = [
    Text({ bold: true }, truncate('Shortcuts', sideContentWidth)),
    Text({}, truncate(' w  WatchCharts', sideContentWidth)),
    Text({}, truncate(' c  Chrono24 market', sideContentWidth)),
    Text({}, truncate(' g  Deploy', sideContentWidth)),
    Text({}, truncate(' a  Add brand', sideContentWidth)),
    Text({}, truncate(' r  Refresh', sideContentWidth)),
    Text({}, truncate(' l  Toggle scroll', sideContentWidth)),
    Text({}, truncate(' q  Quit', sideContentWidth)),
  ];

  const deployPanel = [
    Text({ bold: true }, truncate('Deploy Status', sideContentWidth)),
    Text({ color: 'gray' }, truncate(`service: ${RAILWAY_SERVICE}`, sideContentWidth)),
    Text({ color: 'gray' }, truncate(`catalog: ${catalog?.version || 'missing'}`, sideContentWidth)),
    Text({ color: 'gray' }, truncate(`generated: ${formatTimestamp(catalog?.generatedAt)}`, sideContentWidth)),
    Text({ color: 'gray' }, truncate(`brands: ${catalog?.brands ?? 0} models: ${catalog?.models ?? 0}`, sideContentWidth)),
    Text({ color: 'gray' }, truncate(`last deploy: ${formatTimestamp(deploy?.deployed_at)}`, sideContentWidth)),
    Text(
      { color: deploy?.status === 'error' ? 'red' : 'green' },
      truncate(`status: ${deploy?.status || 'n/a'}`, sideContentWidth)
    ),
    deploy?.error ? Text({ color: 'red' }, truncate(`error: ${deploy.error}`, sideContentWidth)) : null,
  ];

  const modeBanner = mode() !== 'normal'
    ? Box(
        { borderStyle: 'round', padding: 1, marginTop: 1 },
        Text({ bold: true }, mode() === 'confirmDeploy' ? 'Confirm deploy' : 'Add brand'),
        mode() === 'addUrl'
          ? renderTextInput(brandUrlInput, { fullWidth: true, borderStyle: 'round' })
          : null,
        mode() === 'addSlug'
          ? renderTextInput(brandSlugInput, { fullWidth: true, borderStyle: 'round' })
          : null,
        mode() === 'confirmDeploy'
          ? Text({ color: 'yellow' }, 'Press y to deploy, n to cancel')
          : null
      )
    : null;

  return Box(
    { flexDirection: 'column', padding: 1 },
    Box(
      { flexDirection: 'row' },
      Text({ bold: true, color: 'green' }, 'Watchcollection Crawler TUI'),
      Spacer({}),
      Text({ color: 'gray' }, statusMessage())
    ),
    Box(
      { flexDirection: 'row', marginTop: 1 },
      Text({ color: 'gray' }, `Brands: ${list.length}`),
      Text({ color: 'gray' }, ' | '),
      Text({ color: 'green' }, `W ok ${watchSummary.ready}`),
      Text({ color: 'yellow' }, ` run ${watchSummary.running}`),
      Text({ color: 'red' }, ` err ${watchSummary.error}`),
      Text({ color: 'gray' }, ` miss ${watchSummary.missing}`),
      Text({ color: 'gray' }, ' | '),
      Text({ color: 'green' }, `C ok ${chronoSummary.ready}`),
      Text({ color: 'yellow' }, ` run ${chronoSummary.running}`),
      Text({ color: 'red' }, ` err ${chronoSummary.error}`),
      Text({ color: 'gray' }, ` miss ${chronoSummary.missing}`)
    ),
    Box(
      { flexDirection: 'row', marginTop: 1, gap: 2 },
      Box(
        { borderStyle: 'round', padding: 1, width: BRAND_PANEL_WIDTH, height: 18 },
        Text(
          { color: scrollTarget() === 'brands' ? 'yellow' : 'gray' },
          'Brands [l focus | jk scroll]'
        ),
        Scroll(
          {
            ...brandScroll.bind,
            height: BRAND_VIEW_LINES,
            width: BRAND_CONTENT_WIDTH,
            showScrollbar: true,
            scrollbarColor: 'cyan',
            keysEnabled: false,
            isActive: false,
          },
          ...listRows
        )
      ),
      Box({ borderStyle: 'round', padding: 1, flexGrow: 1, height: 18 }, ...detailPanel),
      Box(
        { flexDirection: 'column', width: SIDE_PANEL_WIDTH, height: 18, gap: 1 },
        Box({ borderStyle: 'round', padding: 1, height: 10, width: SIDE_PANEL_WIDTH }, ...shortcutsPanel),
        Box({ borderStyle: 'round', padding: 1, height: 7, width: SIDE_PANEL_WIDTH }, ...deployPanel)
      )
    ),
    Box({ borderStyle: 'round', padding: 1, marginTop: 1, height: 12, width: '100%', flexGrow: 1 },
      Text(
        { color: scrollTarget() === 'logs' ? 'yellow' : 'gray' },
        `Logs [l focus | jk/↑↓ scroll] (last ${LOG_LIMIT} lines)`
      ),
      hiddenLogs > 0 ? Text({ color: 'gray' }, `... ${hiddenLogs} earlier lines hidden`) : null,
      Scroll(
        {
          ...logScroll.bind,
          height: LOG_VIEW_LINES,
          width: logContentWidth,
          showScrollbar: true,
          scrollbarColor: 'cyan',
          keysEnabled: scrollTarget() === 'logs',
          isActive: scrollTarget() === 'logs',
        },
        ...logDisplayLines.map((line) => Text({ color: 'gray' }, line))
      )
    ),
    modeBanner
  );
}

refreshBrands();
setInterval(refreshBrands, 5000);

const { waitUntilExit } = render(App);
await waitUntilExit();
function buildBrandStats(list: BrandEntry[]): Record<string, BrandStats> {
  const stats: Record<string, BrandStats> = {};
  list.forEach((brand) => {
    let total = 0;
    let market = 0;

    if (fs.existsSync(brand.watchchartsFile)) {
      const data = safeReadJson(brand.watchchartsFile);
      const models = Array.isArray(data?.models) ? (data?.models as any[]) : [];
      total = models.length;
    }
    if (fs.existsSync(brand.chrono24File)) {
      const data = safeReadJson(brand.chrono24File);
      const models = Array.isArray(data?.models) ? (data?.models as any[]) : [];
      market = models.filter((m) => m && m.market_price_usd != null).length;
      total = Math.max(total, models.length);
    }

    stats[brand.slug] = { total, market };
  });
  return stats;
}
