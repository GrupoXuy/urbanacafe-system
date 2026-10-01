"use client";
import {useEffect,useState} from "react";
import {createClient} from "@/lib/supabase-browser";

type Session={id:string;opening_amount:number;opened_at:string;status:string;expected_amount:number|null;counted_amount:number|null;difference:number|null};
type Movement={id:string;movement_type:string;amount:number;description:string|null;created_at:string};

export default function Caixa(){
  const [business,setBusiness]=useState("");
  const [session,setSession]=useState<Session|null>(null);
  const [movements,setMovements]=useState<Movement[]>([]);
  const [amount,setAmount]=useState("0");
  const [counted,setCounted]=useState("");
  const [moveType,setMoveType]=useState("deposit");
  const [moveAmount,setMoveAmount]=useState("");
  const [description,setDescription]=useState("");
  const [message,setMessage]=useState("");
  const [saving,setSaving]=useState(false);

  async function load(){
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user)return;
    const {data:m}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(!m)return;
    setBusiness(m.business_id);
    const {data:s}=await c.from("cash_sessions").select("id,opening_amount,opened_at,status,expected_amount,counted_amount,difference").eq("business_id",m.business_id).eq("status","open").maybeSingle();
    setSession(s as Session|null);
    if(s){
      const {data:mv}=await c.from("cash_movements").select("id,movement_type,amount,description,created_at").eq("business_id",m.business_id).eq("cash_session_id",s.id).order("created_at",{ascending:false}).limit(30);
      setMovements((mv||[]) as Movement[]);
    }else setMovements([]);
  }
  useEffect(()=>{load()},[]);

  async function open(){
    setSaving(true);setMessage("");
    const {data,error}=await createClient().rpc("open_cash_session",{p_business_id:business,p_opening_amount:Number(amount)});
    if(error)setMessage(error.message);else setSession(data as Session);
    setSaving(false);load();
  }

  async function close(){
    if(!session)return;
    setSaving(true);setMessage("");
    const {data,error}=await createClient().rpc("close_cash_session",{p_session_id:session.id,p_counted_amount:Number(counted)});
    if(error)setMessage(error.message);else setMessage(`Caixa fechado. Diferença: UYU ${Number(data?.difference||0).toFixed(2)}`);
    setSaving(false);load();
  }

  async function addMovement(){
    if(!session||Number(moveAmount)<=0)return;
    setSaving(true);setMessage("");
    const sign=moveType==="withdrawal"?-1:1;
    const {error}=await createClient().from("cash_movements").insert({
      business_id:business,cash_session_id:session.id,movement_type:moveType,amount:sign*Number(moveAmount),description:description.trim()||null
    });
    if(error)setMessage(error.message);else{setMessage("Movimentação registrada.");setMoveAmount("");setDescription("");load()}
    setSaving(false);
  }

  return <div className="main">
    <h1 className="title">Caixa</h1><p className="subtitle">Abertura, entradas, saídas e fechamento</p>
    <div className="grid section">
      <div className="card"><div className="label">Status</div><div className="value">{session?"Aberto":"Fechado"}</div><p>{session?new Date(session.opened_at).toLocaleString("pt-BR"):"Nenhuma sessão aberta"}</p></div>
      <div className="card"><div className="label">Abertura</div><div className="value">UYU {Number(session?.opening_amount||0).toFixed(2)}</div></div>
      <div className="card"><div className="label">Lançamentos</div><div className="value">{movements.length}</div></div>
    </div>

    {!session ? (
      <div className="card section">
        <h2>Abrir caixa</h2>
        <label className="field"><span>Valor inicial</span><input type="number" min="0" step="0.01" value={amount} onChange={e=>setAmount(e.target.value)}/></label>
        <button className="btn" onClick={open} disabled={!business||saving}>{saving?"Abrindo...":"Abrir caixa"}</button>
      </div>
    ) : (
      <>
        <div className="card section"><h2>Nova movimentação</h2>
          <div className="grid" style={{gridTemplateColumns:"1fr 1fr 2fr auto"}}>
            <label className="field"><span>Tipo</span><select value={moveType} onChange={e=>setMoveType(e.target.value)}><option value="deposit">Depósito</option><option value="withdrawal">Retirada</option><option value="adjustment">Ajuste</option></select></label>
            <label className="field"><span>Valor</span><input type="number" min="0.01" step="0.01" value={moveAmount} onChange={e=>setMoveAmount(e.target.value)}/></label>
            <label className="field"><span>Descrição</span><input value={description} onChange={e=>setDescription(e.target.value)} placeholder="Motivo da movimentação"/></label>
            <div className="field"><span>&nbsp;</span><button className="btn" style={{width:"auto"}} onClick={addMovement} disabled={!moveAmount||saving}>Registrar</button></div>
          </div>
        </div>

        <div className="card section"><h2>Fechar caixa</h2>
          <label className="field"><span>Valor contado</span><input type="number" min="0" step="0.01" value={counted} onChange={e=>setCounted(e.target.value)} /></label>
          <button className="btn" onClick={close} disabled={!counted||saving}>{saving?"Fechando...":"Fechar caixa"}</button>
        </div>

        <div className="section"><h2>Movimentações recentes</h2>
          <table className="table"><thead><tr><th>Data</th><th>Tipo</th><th>Descrição</th><th>Valor</th></tr></thead>
          <tbody>{movements.map(m=><tr key={m.id}><td>{new Date(m.created_at).toLocaleString("pt-BR")}</td><td>{m.movement_type}</td><td>{m.description||"—"}</td><td>{Number(m.amount)>=0?"+":"-"} UYU {Math.abs(Number(m.amount)).toFixed(2)}</td></tr>)}</tbody></table>
        </div>
      </>
    )}
    {message&&<div className="notice">{message}</div>}
  </div>
}