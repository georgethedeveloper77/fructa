"use client";

import { useMemo, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import {
  updatePost, togglePostPublished, deletePost,
  uploadPostCover, removePostCover, type Result,
} from "../actions";
import {
  IconCheck, IconExternal, IconTrash, IconPin, IconClock, IconX,
} from "../../_icons";

export type PostRow = {
  slug: string;
  kind: "article" | "brief";
  title: string;
  excerpt: string | null;
  body: string;
  cover_url: string | null;
  published: boolean;
  published_at: string | null;
  seo_title: string | null;
  seo_description: string | null;
  tags: string[];
  fund_id: string | null;
  company_id: string | null;
  pinned: boolean;
  reading_minutes: number | null;
  updated_at: string;
};

export type LinkOption = { type: "fund" | "company"; id: string; name: string };

const input =
  "w-full rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60";
const area = input + " font-mono text-[13px] leading-relaxed";
const micro = "mb-1.5 block text-[10px] uppercase tracking-wider text-faint";
const goldBtn =
  "rounded-md border border-gold/50 bg-gold/10 px-3.5 py-1.5 text-xs font-medium text-gold hover:bg-gold/20 disabled:opacity-40";
const ghostBtn =
  "rounded-md border border-line px-3 py-1.5 text-xs text-mute hover:text-ink disabled:opacity-40";

function ago(iso: string): string {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 90) return "just now";
  if (s < 3600) return `${Math.round(s / 60)}m`;
  if (s < 86400) return `${Math.round(s / 3600)}h`;
  return `${Math.round(s / 86400)}d`;
}

function readingFor(body: string): number {
  const words = body.trim().split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(words / 200));
}

function Msg({ m }: { m: { ok: boolean; text: string } | null }) {
  if (!m) return null;
  return (
    <span className={"inline-flex items-center gap-1 text-[11px] " + (m.ok ? "text-live" : "text-bad")}>
      {m.ok && <IconCheck size={11} />}
      {m.text}
    </span>
  );
}

function useSaver() {
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const run = (fd: FormData, fn: (f: FormData) => Promise<Result>, okText: string, after?: () => void) =>
    start(async () => {
      const r = await fn(fd);
      setMsg(r.ok ? { ok: true, text: okText } : { ok: false, text: r.error ?? "Failed" });
      if (r.ok) after?.();
    });
  return { pending, msg, setMsg, run };
}

// ── Tag chips ────────────────────────────────────────────────────────────────
function Tags({ value, onChange }: { value: string[]; onChange: (t: string[]) => void }) {
  const [draft, setDraft] = useState("");
  function commit() {
    const t = draft.trim().toLowerCase();
    if (t && !value.includes(t)) onChange([...value, t].slice(0, 12));
    setDraft("");
  }
  return (
    <div className="flex flex-wrap items-center gap-1.5 rounded-md border border-line bg-panel2 px-2 py-1.5">
      {value.map((t) => (
        <span key={t} className="inline-flex items-center gap-1 rounded bg-gold/10 px-2 py-0.5 text-[11px] text-gold">
          {t}
          <button type="button" onClick={() => onChange(value.filter((x) => x !== t))} aria-label={`Remove ${t}`}>
            <IconX size={11} />
          </button>
        </span>
      ))}
      <input
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === ",") { e.preventDefault(); commit(); }
          if (e.key === "Backspace" && !draft && value.length) onChange(value.slice(0, -1));
        }}
        onBlur={commit}
        placeholder="add"
        className="min-w-[52px] flex-1 bg-transparent text-[12px] text-ink outline-none placeholder:text-faint"
      />
    </div>
  );
}

// ── Link picker (fund xor company) ──────────────────────────────────────────
function LinkPicker({
  links, fundId, companyId, onChange,
}: {
  links: LinkOption[];
  fundId: string | null;
  companyId: string | null;
  onChange: (fund: string | null, company: string | null) => void;
}) {
  const value = fundId ? `fund:${fundId}` : companyId ? `company:${companyId}` : "";
  const funds = links.filter((l) => l.type === "fund");
  const companies = links.filter((l) => l.type === "company");
  return (
    <select
      value={value}
      onChange={(e) => {
        const v = e.target.value;
        if (!v) return onChange(null, null);
        const [type, id] = v.split(":");
        type === "fund" ? onChange(id, null) : onChange(null, id);
      }}
      className={input + " appearance-none"}
    >
      <option value="">No link</option>
      <optgroup label="Funds">
        {funds.map((f) => <option key={f.id} value={`fund:${f.id}`}>{f.name}</option>)}
      </optgroup>
      <optgroup label="Companies">
        {companies.map((c) => <option key={c.id} value={`company:${c.id}`}>{c.name}</option>)}
      </optgroup>
    </select>
  );
}

// ── Cover (articles only): bigger preview on the focused editor ─────────────
function Cover({ post }: { post: PostRow }) {
  const [preview, setPreview] = useState<string | null>(null);
  const { pending, msg, run, setMsg } = useSaver();
  const fileRef = useRef<HTMLInputElement>(null);

  function pick(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    setMsg(null);
    setPreview(f ? URL.createObjectURL(f) : null);
  }
  function upload(fd: FormData) {
    fd.set("slug", post.slug);
    run(fd, uploadPostCover, "Uploaded", () => { if (fileRef.current) fileRef.current.value = ""; });
  }
  function remove() {
    const fd = new FormData();
    fd.set("slug", post.slug);
    fd.set("url", post.cover_url ?? "");
    run(fd, removePostCover, "Removed");
  }

  return (
    <div>
      <span className={micro}>Cover</span>
      <div className="overflow-hidden rounded-lg border border-line bg-panel2" style={{ aspectRatio: "16 / 9" }}>
        {preview ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={preview} alt="" className="h-full w-full object-cover" />
        ) : post.cover_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={post.cover_url} alt="" className="h-full w-full object-cover" />
        ) : (
          <div className="flex h-full w-full items-center justify-center text-[11px] text-faint">No cover</div>
        )}
      </div>
      <form action={upload} className="mt-2 flex items-center gap-2">
        <input
          ref={fileRef}
          type="file"
          name="file"
          accept="image/png,image/webp,image/jpeg"
          required
          onChange={pick}
          className="w-full text-[11px] text-faint file:mr-2 file:rounded file:border file:border-line file:bg-panel2 file:px-2 file:py-1 file:text-[11px] file:text-mute"
        />
        <button disabled={pending} className={goldBtn}>{pending ? "…" : "Upload"}</button>
      </form>
      <div className="mt-1 flex items-center gap-3">
        <Msg m={msg} />
        {post.cover_url && (
          <button onClick={remove} disabled={pending} className="text-[11px] text-faint hover:text-bad disabled:opacity-40">
            Remove
          </button>
        )}
      </div>
    </div>
  );
}

// ── App preview (real publish state) ─────────────────────────────────────────
function AppPreview({
  kind, title, summary, reading, published, publishedAt,
}: {
  kind: "article" | "brief"; title: string; summary: string; reading: number;
  published: boolean; publishedAt: string | null;
}) {
  return (
    <div>
      <span className={micro}>In the app</span>
      <div className="rounded-lg border border-line bg-bg p-3">
        <div className="mb-1.5 flex items-center gap-1.5">
          <span className="h-1.5 w-1.5 rounded-full bg-gold" />
          <span className="text-[9px] uppercase tracking-wider text-gold">
            {kind === "article" ? `Article · ${reading} min` : "Brief"}
          </span>
        </div>
        <div className="text-[12px] leading-snug text-ink">{title || "Untitled"}</div>
        {summary && <div className="mt-1 text-[10.5px] leading-snug text-mute">{summary}</div>}
      </div>
      <div className="mt-1.5 flex items-center gap-1.5 text-[10px]">
        <span className={"h-1.5 w-1.5 rounded-full " + (published ? "bg-live" : "bg-faint")} />
        {published
          ? <span className="text-live">Live in app{publishedAt ? ` · ${ago(publishedAt)} ago` : ""}</span>
          : <span className="text-faint">Draft, not in the app yet</span>}
      </div>
    </div>
  );
}

// ── Editor ───────────────────────────────────────────────────────────────────
export function PostEditor({ post, links }: { post: PostRow; links: LinkOption[] }) {
  const router = useRouter();
  const [kind, setKind] = useState<"article" | "brief">(post.kind);
  const [title, setTitle] = useState(post.title);
  const [excerpt, setExcerpt] = useState(post.excerpt ?? "");
  const [bodyV, setBodyV] = useState(post.body ?? "");
  const [tags, setTags] = useState<string[]>(post.tags ?? []);
  const [fundId, setFundId] = useState(post.fund_id);
  const [companyId, setCompanyId] = useState(post.company_id);
  const [pinned, setPinned] = useState(post.pinned);
  const [readOverride, setReadOverride] = useState<string>(post.reading_minutes != null ? String(post.reading_minutes) : "");
  const [seoTitle, setSeoTitle] = useState(post.seo_title ?? "");
  const [seoDesc, setSeoDesc] = useState(post.seo_description ?? "");
  const [seoOpen, setSeoOpen] = useState(false);

  const { pending, msg, run } = useSaver();
  const [busy, start] = useTransition();

  const isArticle = kind === "article";
  const readingAuto = useMemo(() => readingFor(bodyV), [bodyV]);
  const reading = readOverride ? Math.max(1, Math.round(Number(readOverride))) : readingAuto;

  const readingToWrite = readOverride || String(readingAuto);
  const readingStored = post.reading_minutes != null ? String(post.reading_minutes) : String(readingAuto);
  const dirty =
    title !== post.title ||
    excerpt !== (post.excerpt ?? "") ||
    bodyV !== (post.body ?? "") ||
    kind !== post.kind ||
    JSON.stringify(tags) !== JSON.stringify(post.tags ?? []) ||
    fundId !== post.fund_id ||
    companyId !== post.company_id ||
    (isArticle && pinned !== post.pinned) ||
    (isArticle && readingToWrite !== readingStored) ||
    (isArticle && seoTitle !== (post.seo_title ?? "")) ||
    (isArticle && seoDesc !== (post.seo_description ?? ""));

  function save() {
    const fd = new FormData();
    fd.set("slug", post.slug);
    fd.set("kind", kind);
    fd.set("title", title);
    fd.set("excerpt", excerpt);
    fd.set("body", bodyV);
    fd.set("tags", JSON.stringify(tags));
    fd.set("fund_id", fundId ?? "");
    fd.set("company_id", companyId ?? "");
    if (kind === "article") {
      fd.set("pinned", pinned ? "true" : "false");
      fd.set("reading_minutes", readOverride || String(readingAuto));
      fd.set("seo_title", seoTitle);
      fd.set("seo_description", seoDesc);
    }
    run(fd, updatePost, "Saved", () => router.refresh());
  }
  function togglePublish() {
    const fd = new FormData();
    fd.set("slug", post.slug);
    fd.set("value", (!post.published).toString());
    start(async () => { await togglePostPublished(fd); router.refresh(); });
  }
  function del() {
    if (!confirm(`Delete "${post.title}"? This can't be undone.`)) return;
    const fd = new FormData();
    fd.set("slug", post.slug);
    start(async () => { await deletePost(fd); router.push("/admin/blog"); router.refresh(); });
  }

  return (
    <div className="space-y-5">
      {/* header */}
      <div className="flex flex-wrap items-center gap-3">
        <a href="/admin/blog" className="text-sm text-faint hover:text-ink">Back to Blog</a>
        <h1 className="text-xl font-semibold tracking-tight text-ink">Edit post</h1>
        <span className={"rounded-md px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider " +
          (post.published ? "border border-live/40 bg-live/10 text-live" : "border border-line text-faint")}>
          {post.published ? "Published" : "Draft"}
        </span>
        {dirty && <span className="text-[10px] text-gold">unsaved</span>}
        <code className="font-mono text-[11px] text-faint">/blog/{post.slug}</code>
        {post.published && (
          <a href={`/blog/${post.slug}`} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-[11px] text-mute hover:text-gold">
            view <IconExternal size={11} />
          </a>
        )}
        <div className="ml-auto flex items-center gap-2">
          <Msg m={msg} />
          <button
            onClick={save}
            disabled={pending || !dirty}
            className={dirty ? goldBtn : ghostBtn}
            title={dirty ? "Unsaved changes" : "No changes to save"}
          >
            {pending ? "Saving…" : dirty ? "Save" : "Saved"}
          </button>
          <button onClick={togglePublish} disabled={busy} className={ghostBtn}>
            {post.published ? "Unpublish" : "Publish"}
          </button>
          <button onClick={del} disabled={busy} className="inline-flex items-center gap-1 text-[11px] text-faint hover:text-bad disabled:opacity-40">
            <IconTrash size={14} />
          </button>
        </div>
      </div>

      <div className="overflow-hidden rounded-xl border border-line bg-panel">
        <div className="flex">
          {/* main column */}
          <div className="min-w-0 flex-1 border-r border-line p-5">
            <div className="mb-3 inline-flex rounded-md border border-line bg-panel2 p-0.5">
              {(["article", "brief"] as const).map((k) => (
                <button
                  key={k}
                  onClick={() => setKind(k)}
                  className={"rounded px-3 py-1 text-xs capitalize " + (kind === k ? "bg-panel text-ink" : "text-mute")}
                >
                  {k}
                </button>
              ))}
            </div>

            <input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Title"
              className="w-full bg-transparent text-[22px] font-medium tracking-tight text-ink outline-none placeholder:text-faint"
            />
            <div className="mb-4 mt-2 flex flex-wrap items-center gap-3">
              <code className="font-mono text-[11px] text-faint">/blog/{post.slug}</code>
              {isArticle && (
                <button
                  onClick={() => setPinned((v) => !v)}
                  className={"inline-flex items-center gap-1 text-[11px] " + (pinned ? "text-gold" : "text-faint hover:text-mute")}
                >
                  <IconPin size={13} /> {pinned ? "Pinned" : "Pin"}
                </button>
              )}
            </div>

            <label className="mb-4 block">
              <span className={micro}>Summary</span>
              <input
                value={excerpt}
                onChange={(e) => setExcerpt(e.target.value)}
                placeholder="One line, used on the website list and the app briefs rail"
                className={input}
              />
            </label>

            <label className="block">
              <span className={micro}>Body</span>
              <textarea
                rows={isArticle ? 18 : 8}
                value={bodyV}
                onChange={(e) => setBodyV(e.target.value)}
                spellCheck={false}
                className={area}
              />
            </label>

            {isArticle && (
              <div className="mt-4">
                <button onClick={() => setSeoOpen((v) => !v)} className="text-[11px] uppercase tracking-wider text-faint hover:text-mute">
                  SEO {seoOpen ? "−" : "+"}
                </button>
                {seoOpen && (
                  <div className="mt-2 grid grid-cols-2 gap-3">
                    <label className="block">
                      <span className={micro}>SEO title</span>
                      <input value={seoTitle} onChange={(e) => setSeoTitle(e.target.value)} placeholder="Defaults to the title" className={input} />
                    </label>
                    <label className="block">
                      <span className={micro}>SEO description</span>
                      <input value={seoDesc} onChange={(e) => setSeoDesc(e.target.value)} placeholder="Defaults to the summary" className={input} />
                    </label>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* meta rail (roomier than the old inline one) */}
          <div className="flex w-[288px] flex-none flex-col gap-4 p-4">
            <div>
              <span className={micro}>Tags</span>
              <Tags value={tags} onChange={setTags} />
            </div>

            <div>
              <span className={micro}>Link fund or company</span>
              <LinkPicker
                links={links}
                fundId={fundId}
                companyId={companyId}
                onChange={(f, c) => { setFundId(f); setCompanyId(c); }}
              />
            </div>

            {isArticle && (
              <>
                <Cover post={post} />
                <div>
                  <span className={micro}>Reading time</span>
                  <div className="flex items-center gap-2">
                    <div className="inline-flex items-center gap-1.5 text-[13px] text-ink">
                      <IconClock size={13} /> {reading} min
                    </div>
                    <input
                      value={readOverride}
                      onChange={(e) => setReadOverride(e.target.value.replace(/[^0-9]/g, ""))}
                      placeholder={`${readingAuto} auto`}
                      className={input + " ml-auto w-20 text-center"}
                    />
                  </div>
                </div>
              </>
            )}

            <div className="mt-auto">
              <AppPreview
                kind={kind}
                title={title}
                summary={excerpt}
                reading={reading}
                published={post.published}
                publishedAt={post.published_at}
              />
            </div>
          </div>
        </div>

        {/* footer */}
        <div className="flex items-center gap-2 border-t border-line px-5 py-2.5">
          <span className="text-[11px] text-faint">edited {ago(post.updated_at)} ago</span>
          <span className="ml-auto inline-flex items-center gap-1.5 text-[11px]">
            <span className={"h-1.5 w-1.5 rounded-full " + (post.published ? "bg-live" : "bg-faint")} />
            <span className={post.published ? "text-live" : "text-faint"}>
              {post.published ? (post.published_at ? `Live · ${ago(post.published_at)} ago` : "Live") : "Draft"}
            </span>
          </span>
        </div>
      </div>
    </div>
  );
}
