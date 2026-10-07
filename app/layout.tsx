import "./globals.css";
import SpanishUI from "./spanish-ui";
import type { Metadata } from "next";

export const metadata:Metadata={
  title:"Urbana Café | Gestión",
  description:"Sistema operativo, CRM, POS, caja, inventario y producción de Urbana Café y Resto",
  icons:{
    icon:"/urbanacafe-logo.svg",
    shortcut:"/urbanacafe-logo.svg",
    apple:"/urbanacafe-logo.svg"
  },
  openGraph:{
    title:"Urbana Café | Gestión",
    description:"Sistema operativo de Urbana Café y Resto",
    type:"website"
  }
};

export default function RootLayout({children}:{children:React.ReactNode}){
  return <html lang="es-UY"><body><SpanishUI />{children}</body></html>
}