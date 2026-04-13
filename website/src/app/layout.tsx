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
  title: "SpeakType — Talk, and it types for you (Mac)",
  description:
    "Dictate on your Mac and drop text wherever you’re typing. Your voice stays on your device—no cloud required.",
  openGraph: {
    title: "SpeakType",
    description:
      "Dictate on your Mac. Text appears where your cursor is—private and simple.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "SpeakType",
    description:
      "Dictate on your Mac. Text appears where your cursor is—private and simple.",
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
