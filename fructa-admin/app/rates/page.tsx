import { permanentRedirect } from "next/navigation";

// /rates on its own has no content: the rates live per category.
export default function RatesIndex() {
  permanentRedirect("/rates/money-market-funds");
}
