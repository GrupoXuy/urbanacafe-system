"use client";
import {FormEvent,useEffect,useState} from "react";
import {createClient} from "@/lib/supabase-browser";

type Customer={id:string;name:string;phone:string|null;email:string|null;notes:string|null;created_at:string};

export default function Clientes(){
  const [business,setBusiness]=useState("");
  const [items,setItems]=useState<Customer[]>([]);
  const [editing,setEditing]=useState<string|null>(null);
  const [name,setName]=useState("");
  const [phone,setPhone]=useState("");
  const [email,setEmail]=useState("");
  const [notes,setNotes]=useState("");
  const [search,setSearch]=useState("");
  const [message,setMessage]=useState("");
  const [saving,setSaving]=useState(false);

  async function load(){
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user)return;
    const {data:m}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(!m)return;
    setBusiness(m.business_id);
    const {data}=await c.from("customers").select("id,name,phone,email,notes,created_at").eq("business_id",m.business_id).eq("active",true).order("name");
    setItems((data||[]) as Customer[]);
  }
  useEffect(()=>{load()},[]);

  function reset(){setEditing(null);setName("");setPhone("");setEmail("");setNotes("")}
  function edit(c:Customer){setEditing(c.id);setName(c.name);setPhone(c.phone||"");setEmail(c.email||"");setNotes(c.notes||"");window.scrollTo({top:0,behavior:"smooth"})}

  async function save(e:FormEvent){
    e.preventDefault();setSaving(true);setMessage("");
    const c=createClient();
    const payload={business_id:business,name:name.trim(),phone:phone.trim()||null,email:email.trim()||null,notes:notes.trim()||null,active:true};
    const result=editing?await c.from("customers").update(payload).eq("id",editing).eq("business_id",business):await c.from("customers").insert(payload);
    if(result.error)setMessage(result.error.message);
    else{setMessage(editing?"Cliente atualizado.":"Cliente cadastrado.");reset();await load()}
    setSaving(false);
  }

  const filtered=items.filter(c=>[c.name,c.phone||"",c.email||""].join(" ").toLowerCase().includes(search.toLowerCase()));

  return <div className="main">
    <section className="crm-branding">
      <div className="crm-logo-panel"><img src="/urbanacafe-logo.svg" alt="Urbana Café y Resto" /></div>
      <div className="crm-brand-copy">
        <span className="crm-eyebrow">CRM · URBANA CAFÉ</span>
        <h1 className="title">Relación con clientes</h1>
        <p className="subtitle">Centralizá contactos, preferencias y el historial básico de atención de cada cliente.</p>
      </div>
    </section>
    <form className="card section" onSubmit={save}>
      <h2>{editing?"Editar cliente":"Novo cliente"}</h2>
      <div className="grid" style={{gridTemplateColumns:"repeat(3,minmax(0,1fr))"}}>
        <label className="field"><span>Nome</span><input value={name} onChange={e=>setName(e.target.value)} required/></label>
        <label className="field"><span>Telefone</span><input value={phone} onChange={e=>setPhone(e.target.value)} placeholder="+598 ..."/></label>
        <label className="field"><span>E-mail</span><input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="cliente@email.com"/></label>
      </div>
      <label className="field"><span>Observações</span><input value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Preferências ou observações"/></label>
      <div style={{display:"flex",gap:10}}><button className="btn" style={{width:"auto"}} disabled={!business||saving}>{saving?"Salvando...":editing?"Salvar alterações":"Cadastrar cliente"}</button>{editing&&<button type="button" className="btn" style={{width:"auto",background:"#666"}} onClick={reset}>Cancelar</button>}</div>
      {message&&<div className="notice">{message}</div>}
    </form>
    <div className="section">
      <input placeholder="Buscar cliente..." value={search} onChange={e=>setSearch(e.target.value)} style={{width:"100%",padding:12,border:"1px solid #ddd",borderRadius:9,marginBottom:12}}/>
      <table className="table"><thead><tr><th>Nome</th><th>Telefone</th><th>E-mail</th><th>Cadastro</th><th></th></tr></thead><tbody>
        {filtered.map(c=><tr key={c.id}><td><b>{c.name}</b>{c.notes&&<div className="subtitle">{c.notes}</div>}</td><td>{c.phone||"—"}</td><td>{c.email||"—"}</td><td>{new Date(c.created_at).toLocaleDateString("es-UY")}</td><td><button onClick={()=>edit(c)}>Editar</button></td></tr>)}
      </tbody></table>
    </div>
  </div>
}