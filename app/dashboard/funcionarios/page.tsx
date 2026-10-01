"use client";
import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

const roleOptions=["owner","manager","cashier","waiter","stockkeeper","analyst"];
const roleLabel:Record<string,string>={owner:"Proprietário",manager:"Gerente",cashier:"Caixa",waiter:"Atendente",stockkeeper:"Estoque",analyst:"Analista"};
type Member={business_id:string;user_id:string;role:string;active:boolean;created_at:string;profiles?:{full_name:string|null;phone:string|null}|null};

export default function Funcionarios(){
  const [business,setBusiness]=useState(""),[members,setMembers]=useState<Member[]>([]),[email,setEmail]=useState(""),[fullName,setFullName]=useState(""),[phone,setPhone]=useState(""),[role,setRole]=useState("cashier"),[message,setMessage]=useState(""),[loading,setLoading]=useState(true),[sending,setSending]=useState(false);

  async function load(){
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user){setLoading(false);return}
    const {data:m}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(!m){setLoading(false);return}
    setBusiness(m.business_id);
    const {data}=await c.from("business_memberships")
      .select("business_id,user_id,role,active,created_at,profiles(full_name,phone)")
      .eq("business_id",m.business_id).order("created_at",{ascending:true});
    setMembers((data||[]) as Member[]);setLoading(false);
  }
  useEffect(()=>{load()},[]);

  async function invite(){
    setSending(true);setMessage("");
    const r=await fetch("/api/employees",{method:"POST",headers:{"Content-Type":"application/json"},
      body:JSON.stringify({action:"invite",businessId:business,email,fullName,phone,role})});
    const data=await r.json();
    if(!r.ok)setMessage(data.error||"Não foi possível convidar");
    else{setMessage("Convite enviado e funcionário criado.");setEmail("");setFullName("");setPhone("");await load()}
    setSending(false);
  }

  async function updateMember(userId:string,nextRole:string,nextActive:boolean){
    setMessage("");
    const r=await fetch("/api/employees",{method:"POST",headers:{"Content-Type":"application/json"},
      body:JSON.stringify({action:"update",businessId:business,userId,role:nextRole,active:nextActive})});
    const data=await r.json();
    if(!r.ok)setMessage(data.error||"Não foi possível atualizar");else await load();
  }

  return <div className="main">
    <div className="topbar"><div><h1 className="title">Funcionários</h1><p className="subtitle">Equipe, cargos e acesso ao sistema</p></div><Link href="/dashboard" className="btn" style={{width:"auto",textDecoration:"none"}}>Dashboard</Link></div>
    <div className="card section"><h2>Convidar colaborador</h2>
      <div className="grid" style={{gridTemplateColumns:"repeat(4,minmax(0,1fr))"}}>
        <label className="field"><span>Nome</span><input value={fullName} onChange={e=>setFullName(e.target.value)} placeholder="Nome completo"/></label>
        <label className="field"><span>E-mail</span><input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="colaborador@email.com"/></label>
        <label className="field"><span>Telefone</span><input value={phone} onChange={e=>setPhone(e.target.value)} placeholder="+598 ..."/></label>
        <label className="field"><span>Cargo</span><select value={role} onChange={e=>setRole(e.target.value)}>{roleOptions.map(r=><option key={r} value={r}>{roleLabel[r]}</option>)}</select></label>
      </div>
      <button className="btn" onClick={invite} disabled={!business||!fullName||!email||sending}>{sending?"Enviando...":"Enviar convite"}</button>
      {message&&<div className="notice">{message}</div>}
    </div>
    <div className="section"><h2>Equipe cadastrada</h2>
      {loading?<div className="card">Carregando...</div>:<table className="table"><thead><tr><th>Nome</th><th>Contato</th><th>Cargo</th><th>Status</th><th>Alterar</th></tr></thead><tbody>
        {members.map(m=><tr key={m.user_id}><td>{m.profiles?.full_name||"Sem nome"}</td><td>{m.profiles?.phone||"—"}</td><td><select value={m.role} onChange={e=>updateMember(m.user_id,e.target.value,m.active)}>{roleOptions.map(r=><option key={r} value={r}>{roleLabel[r]}</option>)}</select></td><td>{m.active?"Ativo":"Inativo"}</td><td><button className="btn" style={{width:"auto"}} onClick={()=>updateMember(m.user_id,m.role,!m.active)}>{m.active?"Desativar":"Ativar"}</button></td></tr>)}
      </tbody></table>}
    </div>
  </div>
}
