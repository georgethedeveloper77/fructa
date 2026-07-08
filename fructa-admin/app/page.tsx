import type { Metadata } from 'next';
import './landing/landing.css';
import Landing from './landing/Landing';
import { getLandingContent } from './landing/content.server';

export const dynamic = 'force-dynamic';

const SITE = 'https://fructa.africa';

export async function generateMetadata(): Promise<Metadata> {
  const c = await getLandingContent();
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
  const content = await getLandingContent();

  const jsonLd = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'Organization',
        name: content.brand.name,
        url: SITE,
        email: content.brand.contactEmail,
        logo: `${SITE}/icon.png`,
        areaServed: 'KE',
      },
      {
        '@type': 'MobileApplication',
        name: content.brand.name,
        operatingSystem: 'ANDROID, IOS',
        applicationCategory: 'FinanceApplication',
        description: content.seo.description,
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
      <Landing content={content} />
    </>
  );
}
