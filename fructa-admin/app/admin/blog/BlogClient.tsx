"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { createPost, togglePostPublished, deletePost } from "./actions";
import {
  IconArticle, IconBolt, IconPin, IconSearch, IconPlus,
  IconEdit, IconSend, IconTrash, IconCheck,
} from "../_icons";

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

const goldBtn =
  "inline-flex items-center gap-1.5 rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-sm font-medium text-gold hover:bg-gold/20 disabled:opacity-40";
const ghostBtn =
  "inline-flex items-center gap-1.5 rounded-md border border-line bg-panel px-3 py-1.5 text-sm text-mute hover:text-ink disabled:opacity-40";

function ago(iso: string): string {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 90) return "just now";
  if (s < 3600) return `${Math.round(s / 60)}m ago`;
  if (s < 86400) return `${Math.round(s / 3600)}h ago`;
  return `${Math.round(s / 86400)}d ago`;
}

function readingFor(body: string): number {
  const words = body.trim().split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(words / 200));
}

// ── Row thumbnail (bigger, cover-forward) ────────────────────────────────────
function Thumb({ post }: { post: PostRow }) {
  const box = "h-[80px] w-[128px] flex-none overflow-hidden rounded-lg border border-line";
  if (post.cover_url) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={post.cover_url} alt="" className={box + " object-cover"} />;
  }
  const tint = post.kind === "brief" ? "bg-blue/10 text-blue" : "bg-gold/10 text-gold";
  return (
    <div className={box + " flex items-center justify-center " + tint}>
      {post.kind === "brief" ? <IconBolt size={22} /> : <IconArticle size={22} />}
    </div>
  );
}

function buildForm(title: string, kind: "article" | "brief"): FormData {
  const fd = new FormData();
  fd.set("title", title.trim());
  fd.set("kind", kind);
  return fd;
}

// ── Inline creator (title first, then open the editor) ───────────────────────
function Creator({ kind, onCancel }: { kind: "article" | "brief"; onCancel: () => void }) {
  const router = useRouter();
  const [title, setTitle] = useState("");
  const [err, setErr] = useState<string | null>(null);
  const [pending, start] = useTransition();

  function create() {
    if (!title.trim()) { setErr("Give it a title to start."); return; }
    start(async () => {
      const r = await createPost(buildForm(title, kind));
      if (r.ok && r.slug) router.push(`/admin/blog/${r.slug}`);
      else setErr(r.error ?? "Could not create.");
    });
  }

  return (
    <div className="mb-3 rounded-xl border border-dashed border-line2 bg-panel p-4">
      <div className="mb-1.5 text-[10px] uppercase tracking-wider text-faint">New {kind}</div>
      <div className="flex items-center gap-2">
        <input
          autoFocus
          value={title}
          onChange={(e) => { setTitle(e.target.value); setErr(null); }}
          onKeyDown={(e) => { if (e.key === "Enter") create(); if (e.key === "Escape") onCancel(); }}
          placeholder={kind === "article" ? "Understanding net vs gross yield" : "CBK holds the rate at 8.75%"}
          className="w-full rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60"
        />
        <button onClick={create} disabled={pending} className={goldBtn}>
          {pending ? "Creating…" : "Create"}
        </button>
        <button onClick={onCancel} className={ghostBtn}>Cancel</button>
      </div>
      {err && <p className="mt-2 text-xs text-bad">{err}</p>}
    </div>
  );
}

// ── Row ──────────────────────────────────────────────────────────────────────
function Row({ post }: { post: PostRow }) {
  const router = useRouter();
  const [busy, start] = useTransition();

  const reading = post.reading_minutes ?? readingFor(post.body ?? "");
  const fresh = post.published
    ? `live ${post.published_at ? ago(post.published_at) : ""}`.trim()
    : `edited ${ago(post.updated_at)}`;

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
    start(async () => { await deletePost(fd); router.refresh(); });
  }

  return (
    <div className="flex items-center gap-4 rounded-xl border border-line bg-panel p-3.5 transition-colors hover:border-line2 hover:bg-raise">
      <Thumb post={post} />

      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="text-[15.5px] font-semibold tracking-tight text-ink">{post.title || "Untitled"}</span>
          {post.pinned && <span className="text-gold" title="Pinned"><IconPin size={13} /></span>}
        </div>
        <div className="mt-1 flex flex-wrap items-center gap-2 font-mono text-[12px] text-faint">
          <span className={"rounded px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wider " +
            (post.kind === "brief" ? "bg-blue/10 text-blue" : "bg-gold/10 text-gold")}>
            {post.kind}
          </span>
          {post.tags.length > 0 && <span className="text-mute">{post.tags.slice(0, 3).join(", ")}</span>}
          <span>/blog/{post.slug}</span>
        </div>
      </div>

      <div className="flex flex-none flex-col items-end gap-1.5">
        <span className={"inline-flex items-center gap-1.5 rounded-md px-2 py-0.5 font-mono text-[11px] font-semibold uppercase tracking-wider " +
          (post.published ? "bg-live/10 text-live" : "bg-panel2 text-faint")}>
          <span className="h-1.5 w-1.5 rounded-full bg-current" />
          {post.published ? "Published" : "Draft"}
        </span>
        <span className="font-mono text-[11px] text-faint">
          {fresh}{post.kind === "article" ? ` · ${reading} min` : ""}
        </span>
      </div>

      <div className="flex flex-none items-center gap-1.5 border-l border-line pl-3">
        <button
          onClick={() => router.push(`/admin/blog/${post.slug}`)}
          title="Edit"
          className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-line bg-raise text-mute hover:bg-raise2 hover:text-ink"
        >
          <IconEdit size={15} />
        </button>
        <button
          onClick={togglePublish}
          disabled={busy}
          title={post.published ? "Unpublish" : "Publish"}
          className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-line bg-raise text-mute hover:bg-raise2 hover:text-ink disabled:opacity-40"
        >
          {post.published ? <IconCheck size={15} /> : <IconSend size={15} />}
        </button>
        <button
          onClick={del}
          disabled={busy}
          title="Delete"
          className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-line bg-raise text-mute hover:border-bad/40 hover:text-bad disabled:opacity-40"
        >
          <IconTrash size={15} />
        </button>
      </div>
    </div>
  );
}

// ── Root ─────────────────────────────────────────────────────────────────────
export function BlogClient({ posts }: { posts: PostRow[]; links?: LinkOption[] }) {
  const [filter, setFilter] = useState<"all" | "article" | "brief">("all");
  const [q, setQ] = useState("");
  const [creating, setCreating] = useState<"article" | "brief" | null>(null);

  const list = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return posts.filter(
      (p) =>
        (filter === "all" || p.kind === filter) &&
        (!needle || p.title.toLowerCase().includes(needle) || (p.excerpt ?? "").toLowerCase().includes(needle)),
    );
  }, [posts, filter, q]);

  const tab = (k: "all" | "article" | "brief", label: string) => (
    <button
      onClick={() => setFilter(k)}
      className={"mr-4 -mb-px border-b-2 pb-2 text-sm font-medium " +
        (filter === k ? "border-gold text-ink" : "border-transparent text-mute hover:text-ink")}
    >
      {label}
    </button>
  );

  return (
    <div>
      <div className="mb-5 flex items-start gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Blog</h1>
          <p className="mt-1 max-w-2xl text-sm text-mute">
            Articles and briefs, authored once and read by both the website and the app. Publishing
            rebuilds the app snapshot.
          </p>
        </div>
        <div className="ml-auto flex flex-none gap-2">
          <button onClick={() => setCreating("brief")} className={ghostBtn}>
            <IconBolt size={14} /> New brief
          </button>
          <button onClick={() => setCreating("article")} className={goldBtn}>
            <IconPlus size={14} /> New article
          </button>
        </div>
      </div>

      <div className="mb-4 flex items-center gap-3 border-b border-line">
        {tab("all", "All")}
        {tab("article", "Articles")}
        {tab("brief", "Briefs")}
        <div className="ml-auto mb-2 flex w-[230px] items-center gap-2 rounded-md border border-line bg-panel px-3 py-1.5 text-faint">
          <IconSearch size={14} />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search posts"
            className="w-full bg-transparent text-sm text-ink outline-none placeholder:text-faint"
          />
        </div>
        <span className="mb-2 font-mono text-xs text-faint">{list.length} posts</span>
      </div>

      {creating && <Creator kind={creating} onCancel={() => setCreating(null)} />}

      <div className="flex flex-col gap-2.5">
        {list.map((p) => <Row key={p.slug} post={p} />)}
        {list.length === 0 && !creating && (
          <div className="flex flex-col items-center justify-center gap-3 rounded-xl border border-dashed border-line bg-panel py-16 text-mute">
            <IconArticle size={26} />
            <p className="text-sm">No posts match. Start a new one.</p>
          </div>
        )}
      </div>
    </div>
  );
}
