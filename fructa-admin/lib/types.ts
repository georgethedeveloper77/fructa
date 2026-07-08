// Mirrors the SQL schema + the JSON contract. Keep in sync with the Flutter models.
export type FundCategory = "mmf_kes" | "mmf_usd" | "bond" | "tbill" | "sacco" | "stock" | "insurance";
export type FundStatus = "live" | "stale" | "hidden";
export type Currency = "KES" | "USD";
export type CompanyType = "fund_manager" | "insurer" | "sacco" | "government";
export type SignalTag = "STRENGTH" | "WATCH" | "NOTE";

export interface Fund {
  id: string;
  name: string;
  manager: string;
  category: FundCategory;
  currency: Currency;
  current_rate: number | null;
  tax_free: boolean;
  min_invest: number | null;
  mgmt_fee: number | null;
  aum: string | null;
  withdraw_note: string | null;
  site_url: string | null;
  invest_url: string | null;
  contact_url: string | null;
  logo_domain: string | null;
  company_id: string | null;
  verified: boolean;
  featured: boolean;
  status: FundStatus;
  updated_at: string;
}

export interface RateHistory {
  id: number;
  fund_id: string;
  rate: number;
  as_of: string; // YYYY-MM-DD
  source: string | null;
  source_url: string | null;
}

export interface Company {
  id: string;
  name: string;
  type: CompanyType;
  brand_color: string | null;
  logo_url: string | null;
  website: string | null;
  verified: boolean;
}

export interface Agent {
  id: string;
  name: string;
  role: string | null;
  phone: string | null;
  whatsapp: boolean;
  photo_url: string | null;
  active: boolean;
  is_free: boolean;
}

export interface InsightTemplate {
  id: number;
  key: string;
  tag: SignalTag;
  template: string;
  active: boolean;
}
