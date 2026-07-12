import type { Metadata } from 'next';
import { cache } from 'react';
import './landing/landing.css';
import Landing from './landing/Landing';
import { getLandingContent } from './landing/content.server';
import { getLandingCharts } from './landing/charts.server';

export const dynamic = 'force-dynamic';

const SITE = 'https://fructa.africa';

// generateMetadata and the page body both need the content, and Next runs them
// in the same request. cache() collapses that into one app_config read instead
// of two. The charts read is separate and only the body needs it.
const content = cache(getLandingContent);
const charts = cache(getLandingCharts);

export async function generateMetadata(): Promise<Metadata> {
  const c = await content();
  const og = c.seo.ogImage ?? `${SITE}/og.png`;
  return {
    metadataBase: new URL(SITE),
    title: c.seo.title,
    description: c.seo.description,
    applicationName: c.brand.name,
    keywords: [
      'Kenya money market fund rates',
      'MMF rates Kenya',
      'T-bill rates Kenya',
      'SACCO dividend rates',
      'Kenya investment yields',
      'Fructa',
    ],
    alternates: { canonical: '/' },
    openGraph: {
      type: 'website',
      url: SITE,
      siteName: c.brand.name,
      title: c.seo.title,
      description: c.seo.description,
      images: [{ url: og, width: 1200, height: 630, alt: c.seo.title }],
    },
    twitter: {
      card: 'summary_large_image',
      title: c.seo.title,
      description: c.seo.description,
      images: [og],
    },
    icons: { icon: '/icon.png', apple: '/apple-icon.png', shortcut: '/favicon.ico' },
    robots: { index: true, follow: true },
  };
}

export default async function Page() {
  const [c, ch] = await Promise.all([content(), charts()]);

  const jsonLd = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'Organization',
        name: c.brand.name,
        url: SITE,
        email: c.brand.contactEmail,
        logo: `${SITE}/icon.png`,
        areaServed: 'KE',
      },
      {
        '@type': 'MobileApplication',
        name: c.brand.name,
        operatingSystem: 'ANDROID, IOS',
        applicationCategory: 'FinanceApplication',
        description: c.seo.description,
        offers: { '@type': 'Offer', price: '0', priceCurrency: 'KES' },
      },
    ],
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <Landing content={c} charts={ch} />
    </>
  );
}
