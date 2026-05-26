import type { Metadata } from "next";
import { MinimalLanding } from "@/features/landing/components/minimal-landing";
import { RedirectIfAuthenticated } from "@/features/landing/components/redirect-if-authenticated";

export const metadata: Metadata = {
  title: {
    absolute: "魔法笔记",
  },
  alternates: {
    canonical: "/",
  },
};

export default function LandingPage() {
  return (
    <>
      <RedirectIfAuthenticated />
      <MinimalLanding />
    </>
  );
}
