"use client";
import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

type Payment={method:string;amount:number};
type Sale={id:string;created_at:string;total:number;status:"open"|"completed"|"cancelled"|"refunded";notes:string|null;customers?:{name:string}|null;sale_payments?:Payment[]};

const methodLabel:Record<string,string>={
  cash:"Dinheiro",debit:"Débito",credit:"Crédito",transfer:"Transferência",mercado_pago:"Mercado Pago",other:"Outro"
};

export default function Vendas(){
  const [business,setBusiness]=useState("");
  const [sales,setSales]=useState<Sale[]>([]);
  const [loading,setLoading]=useState(true);
  const [saving,setSaving]=useState("");
  const [message,setMessage]=useState("");

  async function load(){
    setLoading(true);setMessage("");
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user){setLoading(false);return}

    const {data:m,error:me}=await c.from("business_memberships")
      .select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(me||!m){setMessage(me?.message||"Negócio não encontrado");setLoading(false);return}
    setBusiness(m.business_id);

    const {data,error}=await c.from("sales")
      .select("id,created_at,total,status,notes,customers(name),sale_payments(method,amount)")
      .eq("business_id",m.business_id)
      .in("status",["completed","cancelled","refunded"])
      .order("created_at",{ascending:false})
      .limit(100);

    if(error)setMessage(error.message);
    setSales((data||[]) as Sale[]);
    setLoading(false);
  }

  useEffect(()=>{load()},[]);

  async function refund(sale:Sale){
    const confirmed=window.confirm(
      `Estornar a venda de UYU ${Number(sale.total).toFixed(2)}? O estoque será recomposto e, quando aplicável, o caixa receberá um lançamento de devolução.`
    );
    if(!confirmed)return;

    const reason=window.prompt("Motivo do estorno:", "Solicitação de cliente");
    if(reason===null)return;

    setSaving(sale.id);setMessage("");
    const {error}=await createClient().rpc("refund_sale_transaction",{
      p_sale_id:sale.id,
      p_reason:reason.trim()||"Estorno de venda"
    });
    if(error)setMessage(error.message);
    else{setMessage("Venda estornada e movimentos compensatórios registrados.");await load()}
    setSaving("");
  }

  return <div className="main">
    <div className="topbar">
      <div><h1 className="title">Histórico de vendas</h1><p className="subtitle">Consulta, pagamentos e estornos compensatórios</p></div>
      <div style={{display:"flex",gap:10}}>
        <Link href="/dashboard/pos" className="btn" style={{width:"auto",textDecoration:"none"}}>Abrir POS</Link>
        <Link href="/dashboard" className="btn" style={{width:"auto",textDecoration:"none"}}>Dashboard</Link>
      </div>
    </div>

    {message&&<div className="notice">{message}</div>}

    <div className="section">
      {loading?<div className="card">Carregando vendas...</div>:
      <div className="card" style={{overflowX:"auto"}}>
        <table className="table">
          <thead><tr><th>Data</th><th>Cliente</th><th>Total</th><th>Pagamento</th><th>Status</th><th>Ação</th></tr></thead>
          <tbody>
            {sales.map(sale=>{
              const payment=sale.sale_payments?.[0];
              return <tr key={sale.id}>
                <td>{new Date(sale.created_at).toLocaleString("pt-BR")}</td>
                <td>{sale.customers?.name||"Consumidor final"}</td>
                <td>UYU {Number(sale.total).toFixed(2)}</td>
                <td>{payment?methodLabel[payment.method]||payment.method:"—"}</td>
                <td>{sale.status==="completed"?"Concluída":sale.status==="refunded"?"Estornada":"Cancelada"}</td>
                <td>
                  {sale.status==="completed"
                    ?<button onClick={()=>refund(sale)} disabled={saving===sale.id}>{saving===sale.id?"Estornando...":"Estornar"}</button>
                    :<span className="subtitle">Sem ação</span>}
                </td>
              </tr>
            })}
            {!sales.length&&<tr><td colSpan={6}>Nenhuma venda encontrada.</td></tr>}
          </tbody>
        </table>
      </div>}
    </div>
  </div>
}
