"use client";
import {FormEvent,useEffect,useState} from "react";
import {createClient} from "@/lib/supabase-browser";

type TableRow={id:string;name:string;seats:number|null;active:boolean};

export default function Mesas(){
  const [business,setBusiness]=useState("");
  const [items,setItems]=useState<TableRow[]>([]);
  const [name,setName]=useState("");
  const [seats,setSeats]=useState("2");
  const [message,setMessage]=useState("");
  const [saving,setSaving]=useState(false);

  async function load(){
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user)return;
    const {data:m}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(!m)return;
    setBusiness(m.business_id);
    const {data}=await c.from("cafe_tables").select("id,name,seats,active").eq("business_id",m.business_id).order("name");
    setItems((data||[]) as TableRow[]);
  }
  useEffect(()=>{load()},[]);

  async function save(e:FormEvent){
    e.preventDefault();setSaving(true);setMessage("");
    const {error}=await createClient().from("cafe_tables").insert({business_id:business,name:name.trim(),seats:Number(seats)||null,active:true});
    if(error)setMessage(error.message);else{setMessage("Mesa cadastrada.");setName("");setSeats("2");load()}
    setSaving(false);
  }
  async function toggle(t:TableRow){
    const {error}=await createClient().from("cafe_tables").update({active:!t.active}).eq("id",t.id).eq("business_id",business);
    if(error)setMessage(error.message);else load();
  }

  return <div className="main">
    <div className="topbar"><div><h1 className="title">Mesas</h1><p className="subtitle">Mapa operacional de mesas e capacidade</p></div></div>
    <form className="card section" onSubmit={save}>
      <h2>Nova mesa</h2>
      <div className="grid" style={{gridTemplateColumns:"2fr 1fr auto"}}>
        <label className="field"><span>Nome</span><input value={name} onChange={e=>setName(e.target.value)} placeholder="Mesa 01" required/></label>
        <label className="field"><span>Lugares</span><input type="number" min="1" value={seats} onChange={e=>setSeats(e.target.value)}/></label>
        <div className="field"><span>&nbsp;</span><button className="btn" style={{width:"auto"}} disabled={!business||saving}>{saving?"Salvando...":"Cadastrar mesa"}</button></div>
      </div>
      {message&&<div className="notice">{message}</div>}
    </form>
    <div className="grid section">{items.map(t=><div className="card" key={t.id}><div className="label">Mesa</div><div className="value">{t.name}</div><p>{t.seats||"—"} lugares</p><p>{t.active?"Disponível no sistema":"Inativa"}</p><button className="btn" onClick={()=>toggle(t)}>{t.active?"Desativar":"Ativar"}</button></div>)}</div>
  </div>
}