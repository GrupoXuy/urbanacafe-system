import "./globals.css";
import SpanishUI from "./spanish-ui";
import type { Metadata } from "next";
export const metadata:Metadata={title:"Urbana Café | Gestión",description:"CRM, POS, caja, inventario y gestión de Urbana Café"};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="es-UY"><body><SpanishUI />{children}</body></html>}