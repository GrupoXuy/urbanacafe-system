import "./globals.css";
import SpanishUI from "./spanish-ui";
import type { Metadata } from "next";
export const metadata:Metadata={title:"Urbana Café | Gestão",description:"CRM, POS, caixa, estoque e gestão do Urbana Café"};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="es-UY"><body><SpanishUI />{children}</body></html>}