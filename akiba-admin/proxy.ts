import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

// Next.js 16: this file is `proxy.ts` (formerly middleware.ts), named export `proxy`,
// runs on the Node.js runtime. Kept for redirect UX only — real authorization must
// also be enforced inside each server action / route (CVE-2025-29927).
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // If env is missing, DON'T throw (that is what was 500-ing /login).
  // Let the request through; the pages will surface a clearer error, and the
  // deploy config is the real fix.
  if (!url || !anon) {
    console.error(
      "[proxy] Missing NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY — auth gating skipped.",
    );
    return response;
  }

  const supabase = createServerClient(url, anon, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
      },
    },
  });

  // getUser() also refreshes the session cookie. Never let a transient Supabase
  // error take down the whole matched route.
  let user = null;
  try {
    const { data } = await supabase.auth.getUser();
    user = data.user;
  } catch (err) {
    console.error("[proxy] supabase.auth.getUser failed:", err);
    return response; // fail open on the redirect layer; pages/actions still guard
  }

  const path = request.nextUrl.pathname;
  const adminEmail = process.env.ADMIN_EMAIL; // optional owner allowlist
  const allowed = !!user && (!adminEmail || user.email === adminEmail);

  // Gate the admin area.
  if (path.startsWith("/admin") && !allowed) {
    const to = request.nextUrl.clone();
    to.pathname = "/login";
    return NextResponse.redirect(to);
  }

  // Don't show the login page to someone already signed in.
  if (path === "/login" && allowed) {
    const to = request.nextUrl.clone();
    to.pathname = "/admin";
    return NextResponse.redirect(to);
  }

  return response;
}

export const config = {
  matcher: ["/admin/:path*", "/login"],
};
