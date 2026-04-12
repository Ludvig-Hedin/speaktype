import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "SpeakType — Offline voice-to-text for Mac",
  description:
    "Privacy-first dictation for macOS. Whisper runs locally—press a hotkey, speak, paste anywhere.",
  openGraph: {
    title: "SpeakType",
    description:
      "Fast, offline voice-to-text for macOS. No cloud. No tracking.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "SpeakType",
    description:
      "Fast, offline voice-to-text for macOS. No cloud. No tracking.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} min-h-screen antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
