"use client";

import { useRef, useState, useTransition } from "react";
import {
  savePage, createPost, updatePost, togglePostPublished, deletePost,
  uploadPostCover, removePostCover, type Result,
} from "./actions";
import { IconCheck, IconPlus, IconExternal } from "../_icons";

export type PageRow = { slug: string; title: string; body: string; updated_at: string };
export type PostRow = {
  slug: string; title: string; excerpt: string | null; body: string; cover_url: string | null;
  published: boolean; published_at: string | null; seo_title: string | null; seo_description: string | null;
  updated_at: string;
};

const input =
  "w-full rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60";
const area = input + " font-mono text-[13px] leading-relaxed";
const micro = "mb-1 block text-[10px] uppercase tracking-wider text-faint";
const saveBtn =
  "rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-xs font-medium text-gold hover:bg-gold/20 disabled:opacity-40";

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

// ── Pages ────────────────────────────────────────────────────────────────────
function PageEditor({ page }: { page: PageRow }) {
  const [title, setTitle] = useState(page.title);
  const [bodyV, setBodyV] = useState(page.body);
  const { pending, msg, run } = useSaver();

  function save() {
    const fd = new FormData();
    fd.set("slug", page.slug);
    fd.set("title", title);
    fd.set("body", bodyV);
    run(fd, savePage, "Saved");
  }

  return (
    <div className="rounded-xl border border-line bg-panel p-4">
      <div className="mb-3 flex items-center justify-between">
        <code className="font-mono text-[11px] text-faint">/{page.slug}</code>
        <a href={`/${page.slug}`} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-[11px] text-mute hover:text-gold">
          view <IconExternal size={11} />
        </a>
      </div>
      <label className="mb-3 block">
        <span className={micro}>Title</span>
        <input value={title} onChange={(e) => setTitle(e.target.value)} className={input} />
      </label>
      <label className="block">
        <span className={micro}>Body (Markdown)</span>
        <textarea rows={12} value={bodyV} onChange={(e) => setBodyV(e.target.value)} className={area} spellCheck={false} />
      </label>
      <div className="mt-3 flex items-center gap-3">
        <button onClick={save} disabled={pending} className={saveBtn}>Save &amp; publish</button>
        <Msg m={msg} />
      </div>
    </div>
  );
}

// ── Blog: cover ──────────────────────────────────────────────────────────────
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
    run(fd, uploadPostCover, "Uploaded", () => {
      if (fileRef.current) fileRef.current.value = "";
    });
  }
  function remove() {
    const fd = new FormData();
    fd.set("slug", post.slug);
    fd.set("url", post.cover_url ?? "");
    run(fd, removePostCover, "Removed");
  }

  return (
    <div className="flex items-start gap-4">
      <div className="overflow-hidden rounded-lg border border-line bg-panel2" style={{ aspectRatio: "16 / 8", width: 200 }}>
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
      <div className="flex flex-col gap-2">
        <span className={micro}>Cover image</span>
        <form action={upload} className="flex items-center gap-2">
          <input
            ref={fileRef}
            type="file"
            name="file"
            accept="image/png,image/webp,image/jpeg"
            required
            onChange={pick}
            className="w-40 text-xs text-faint file:mr-2 file:rounded file:border file:border-line file:bg-panel2 file:px-2 file:py-1 file:text-xs file:text-mute"
          />
          <button disabled={pending} className={saveBtn}>{pending ? "…" : "Upload"}</button>
        </form>
        <Msg m={msg} />
        {post.cover_url && (
          <button onClick={remove} disabled={pending} className="text-left text-xs text-faint hover:text-bad disabled:opacity-40">
            Remove
          </button>
        )}
      </div>
    </div>
  );
}

// ── Blog: post ───────────────────────────────────────────────────────────────
function PostEditor({ post }: { post: PostRow }) {
  const [title, setTitle] = useState(post.title);
  const [excerpt, setExcerpt] = useState(post.excerpt ?? "");
  const [bodyV, setBodyV] = useState(post.body);
  const [seoTitle, setSeoTitle] = useState(post.seo_title ?? "");
  const [seoDesc, setSeoDesc] = useState(post.seo_description ?? "");
  const { pending, msg, run } = useSaver();
  const [busy, start] = useTransition();

  function save() {
    const fd = new FormData();
    fd.set("slug", post.slug);
    fd.set("title", title);
    fd.set("excerpt", excerpt);
    fd.set("body", bodyV);
    fd.set("seo_title", seoTitle);
    fd.set("seo_description", seoDesc);
    run(fd, updatePost, "Saved");
  }
  function togglePublish() {
    const fd = new FormData();
    fd.set("slug", post.slug);
    fd.set("value", (!post.published).toString());
    start(() => togglePostPublished(fd));
  }
  function del() {
    if (!confirm(`Delete "${post.title}"? This can't be undone.`)) return;
    const fd = new FormData();
    fd.set("slug", post.slug);
    start(() => deletePost(fd));
  }

  return (
    <div className="rounded-xl border border-line bg-panel p-4">
      <div className="mb-3 flex items-center gap-3">
        <span
          className={
            "rounded-md px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider " +
            (post.published ? "border border-live/40 bg-live/10 text-live" : "border border-line text-faint")
          }
        >
          {post.published ? "Published" : "Draft"}
        </span>
        <code className="font-mono text-[11px] text-faint">/blog/{post.slug}</code>
        {post.published && (
          <a href={`/blog/${post.slug}`} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-[11px] text-mute hover:text-gold">
            view <IconExternal size={11} />
          </a>
        )}
        <div className="ml-auto flex items-center gap-2">
          <button onClick={togglePublish} disabled={busy} className="rounded-md border border-line px-2.5 py-1 text-xs text-mute hover:text-ink disabled:opacity-40">
            {post.published ? "Unpublish" : "Publish"}
          </button>
          <button onClick={del} disabled={busy} className="text-xs text-faint hover:text-bad disabled:opacity-40">Delete</button>
        </div>
      </div>

      <div className="space-y-3">
        <label className="block">
          <span className={micro}>Title</span>
          <input value={title} onChange={(e) => setTitle(e.target.value)} className={input} />
        </label>
        <label className="block">
          <span className={micro}>Excerpt</span>
          <input value={excerpt} onChange={(e) => setExcerpt(e.target.value)} placeholder="One-line summary for the list + search cards" className={input} />
        </label>
        <Cover post={post} />
        <label className="block">
          <span className={micro}>Body (Markdown)</span>
          <textarea rows={12} value={bodyV} onChange={(e) => setBodyV(e.target.value)} className={area} spellCheck={false} />
        </label>
        <div className="grid grid-cols-2 gap-3">
          <label className="block">
            <span className={micro}>SEO title (optional)</span>
            <input value={seoTitle} onChange={(e) => setSeoTitle(e.target.value)} placeholder="Defaults to the title" className={input} />
          </label>
          <label className="block">
            <span className={micro}>SEO description (optional)</span>
            <input value={seoDesc} onChange={(e) => setSeoDesc(e.target.value)} placeholder="Defaults to the excerpt" className={input} />
          </label>
        </div>
      </div>

      <div className="mt-4 flex items-center gap-3">
        <button onClick={save} disabled={pending} className={saveBtn}>Save</button>
        <Msg m={msg} />
      </div>
    </div>
  );
}

function CreatePost() {
  const [title, setTitle] = useState("");
  const [slug, setSlug] = useState("");
  const { pending, msg, run } = useSaver();

  function create() {
    const fd = new FormData();
    fd.set("title", title);
    fd.set("slug", slug);
    run(fd, createPost, "Created draft", () => {
      setTitle("");
      setSlug("");
    });
  }

  return (
    <div className="rounded-xl border border-dashed border-line bg-panel p-4">
      <p className="mb-3 text-[11px] uppercase tracking-wider text-faint">New post</p>
      <div className="flex flex-wrap items-end gap-3">
        <label className="min-w-[220px] flex-1">
          <span className={micro}>Title</span>
          <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Understanding net vs gross yield" className={input} />
        </label>
        <label className="w-[220px]">
          <span className={micro}>Slug (optional)</span>
          <input value={slug} onChange={(e) => setSlug(e.target.value)} placeholder="auto from title" className={input} />
        </label>
        <button onClick={create} disabled={pending} className={"inline-flex items-center gap-1 " + saveBtn}>
          <IconPlus size={13} /> Create draft
        </button>
      </div>
      <div className="mt-2"><Msg m={msg} /></div>
    </div>
  );
}

export function ContentClient({ pages, posts }: { pages: PageRow[]; posts: PostRow[] }) {
  return (
    <div className="space-y-8">
      <section className="space-y-3">
        <div className="flex items-center gap-2">
          <span className="text-[11px] uppercase tracking-wider text-gold">Pages</span>
          <span className="tnum text-[11px] text-faint">{pages.length}</span>
          <div className="h-px flex-1 bg-line" />
        </div>
        {pages.map((p) => (
          <PageEditor key={p.slug} page={p} />
        ))}
      </section>

      <section className="space-y-3">
        <div className="flex items-center gap-2">
          <span className="text-[11px] uppercase tracking-wider text-gold">Blog</span>
          <span className="tnum text-[11px] text-faint">{posts.length}</span>
          <div className="h-px flex-1 bg-line" />
        </div>
        <CreatePost />
        {posts.map((p) => (
          <PostEditor key={p.slug} post={p} />
        ))}
        {posts.length === 0 && (
          <p className="rounded-xl border border-line bg-panel px-4 py-8 text-center text-sm text-mute">
            No posts yet. Create your first draft above.
          </p>
        )}
      </section>
    </div>
  );
}
