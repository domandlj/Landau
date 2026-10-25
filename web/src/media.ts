// Pictures and videos in text blocks: ![caption](src). The src is a web
// address, or a path into modules/, like media/projectile.gif, whose files
// are built into the app.

const FILES = import.meta.glob("../../modules/media/*.{png,jpg,jpeg,gif,svg,webp,mp4,webm}", {
  query: "?url",
  import: "default",
  eager: true,
}) as Record<string, string>;

const BY_PATH: Record<string, string> = Object.fromEntries(
  Object.entries(FILES).map(([path, url]) => [path.replace(/^.*\/modules\//, ""), url]),
);

export type Media =
  | { kind: "image" | "video"; url: string }
  | { kind: "embed"; url: string } // a YouTube or Vimeo player
  | { kind: "missing"; src: string };

const VIDEO = /\.(mp4|webm)(\?.*)?$/i;

function youtube(u: URL): string | null {
  const host = u.hostname.replace(/^www\.|^m\./, "");
  const id =
    host === "youtu.be" ? u.pathname.slice(1)
    : host === "youtube.com" && u.pathname === "/watch" ? u.searchParams.get("v")
    : host === "youtube.com" && u.pathname.startsWith("/shorts/") ? u.pathname.split("/")[2]
    : null;
  return id && /^[\w-]+$/.test(id) ? `https://www.youtube-nocookie.com/embed/${id}` : null;
}

function vimeo(u: URL): string | null {
  const id = u.hostname.replace(/^www\./, "") === "vimeo.com" ? u.pathname.slice(1) : null;
  return id && /^\d+$/.test(id) ? `https://player.vimeo.com/video/${id}` : null;
}

export function media(src: string): Media {
  if (/^https?:\/\//i.test(src)) {
    const u = new URL(src);
    const player = youtube(u) ?? vimeo(u);
    if (player) return { kind: "embed", url: player };
    return { kind: VIDEO.test(u.pathname) ? "video" : "image", url: src };
  }
  const url = BY_PATH[src.replace(/^\.\//, "")];
  if (!url) return { kind: "missing", src };
  return { kind: VIDEO.test(src) ? "video" : "image", url };
}
