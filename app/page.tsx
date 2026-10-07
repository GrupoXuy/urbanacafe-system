import Link from "next/link";

const highlights=[
  {title:"Operación",text:"POS, comandas, caja e inventario en un mismo flujo."},
  {title:"Clientes",text:"CRM para centralizar contactos y el historial de atención."},
  {title:"Producción",text:"KDS para cocina y bar con seguimiento operativo."}
];

export default function Home(){
  return <main className="home-landing">
    <div className="home-glow home-glow-one" aria-hidden="true"/>
    <div className="home-glow home-glow-two" aria-hidden="true"/>
    <section className="home-hero">
      <div className="home-brand">
        <div className="home-logo-wrap">
          <img src="/urbanacafe-logo.svg" alt="Urbana Café y Resto" className="home-logo"/>
        </div>
        <span className="home-eyebrow">SISTEMA OPERATIVO</span>
        <h1>Todo lo que Urbana necesita para operar mejor.</h1>
        <p className="home-copy">Gestión de ventas, clientes, inventario y producción en una sola plataforma, pensada para la operación diaria de Urbana Café.</p>
        <div className="home-meta">
          <span>25 de Mayo 263 · Montevideo</span>
          <span>Salón · Delivery</span>
        </div>
        <Link href="/login" className="home-cta">Entrar al sistema <span aria-hidden="true">→</span></Link>
      </div>
      <div className="home-cards" aria-label="Módulos principales">
        {highlights.map(item=><article className="home-card" key={item.title}>
          <div className="home-card-dot" aria-hidden="true"/>
          <h2>{item.title}</h2>
          <p>{item.text}</p>
        </article>)}
      </div>
      <div className="home-footer">URBANA CAFÉ Y RESTO <span>·</span> MONTEVIDEO, URUGUAY</div>
    </section>
  </main>;
}