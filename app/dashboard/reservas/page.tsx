"use client";
import {FormEvent,useEffect,useState} from "react";
import {createClient} from "@/lib/supabase-browser";

type Customer={id:string;name:string};
type TableRow={id:string;name:string;seats:number|null};
type Reservation={id:string;customer_id:string|null;table_id:string|null;reservation_at:string;party_size:number;status:string;notes:string|null;customers?:{name:string}|null;cafe_tables?:{name:string}|null};

const statuses=[["pending","Pendente"],["confirmed","Confirmada"],["seated","Sentada"],["completed","Concluída"],["cancelled","Cancelada"]];

export default function Reservas(){
  const [business,setBusiness]=useState("");
  const [items,setItems]=useState<Reservation[]>([]);
  const [customers,setCustomers]=useState<Customer[]>([]);
  const [tables,setTables]=useState<TableRow[]>([]);
  const [customer,setCustomer]=useState("");
  const [table,setTable]=useState("");
  const [date,setDate]=useState("");
  const [partySize,setPartySize]=useState("2");
  const [notes,setNotes]=useState("");
  const [message,setMessage]=useState("");
  const [saving,setSaving]=useState(false);

  async function load(){
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user)return;
    const {data:m}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(!m)return;
    setBusiness(m.business_id);
    const [{data:r},{data:cs},{data:ts}]=await Promise.all([
      c.from("reservations").select("id,customer_id,table_id,reservation_at,party_size,status,notes,customers(name),cafe_tables(name)").eq("business_id",m.business_id).order("reservation_at",{ascending:true}).limit(100),
      c.from("customers").select("id,name").eq("business_id",m.business_id).eq("active",true).order("name"),
      c.from("cafe_tables").select("id,name,seats").eq("business_id",m.business_id).eq("active",true).order("name")
    ]);
    setItems((r||[]) as Reservation[]);
    setCustomers((cs||[]) as Customer[]);
    setTables((ts||[]) as TableRow[]);
  }
  useEffect(()=>{load()},[]);

  async function save(e:FormEvent){
    e.preventDefault();
    setSaving(true);setMessage("");
    if(!date){setMessage("Informe data e hora da reserva.");setSaving(false);return}
    const {error}=await createClient().from("reservations").insert({
      business_id:business,customer_id:customer||null,table_id:table||null,reservation_at:new Date(date).toISOString(),party_size:Number(partySize)||2,status:"pending",notes:notes.trim()||null
    });
    if(error)setMessage(error.message);
    else{setMessage("Reserva cadastrada.");setCustomer("");setTable("");setPartySize("2");setNotes("");await load()}
    setSaving(false);
  }

  async function changeStatus(id:string,status:string){
    const {error}=await createClient().from("reservations").update({status}).eq("id",id).eq("business_id",business);
    if(error)setMessage(error.message);else load();
  }

  return <div className="main">
    <div className="topbar"><div><h1 className="title">Reservas</h1><p className="subtitle">Agenda de clientes, mesas e horários</p></div></div>
    <form className="card section" onSubmit={save}>
      <h2>Nova reserva</h2>
      <div className="grid" style={{gridTemplateColumns:"repeat(4,minmax(0,1fr))"}}>
        <label className="field"><span>Cliente</span><select value={customer} onChange={e=>setCustomer(e.target.value)}><option value="">Sem cliente</option>{customers.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
        <label className="field"><span>Mesa</span><select value={table} onChange={e=>setTable(e.target.value)}><option value="">Sem mesa</option>{tables.map(t=><option key={t.id} value={t.id}>{t.name}{t.seats ? " — "+t.seats+" lugares" : ""}</option>)}</select></label>
        <label className="field"><span>Data e hora</span><input type="datetime-local" value={date} onChange={e=>setDate(e.target.value)} required/></label>
        <label className="field"><span>Pessoas</span><input type="number" min="1" value={partySize} onChange={e=>setPartySize(e.target.value)}/></label>
      </div>
      <label className="field"><span>Observações</span><input value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Aniversário, preferência, contato etc."/></label>
      <button className="btn" style={{width:"auto"}} disabled={!business||saving}>{saving?"Salvando...":"Cadastrar reserva"}</button>
      {message&&<div className="notice">{message}</div>}
    </form>
    <div className="section">
      <table className="table"><thead><tr><th>Data</th><th>Cliente</th><th>Mesa</th><th>Pessoas</th><th>Status</th><th>Observação</th></tr></thead>
      <tbody>{items.map(r=><tr key={r.id}><td>{new Date(r.reservation_at).toLocaleString("pt-BR")}</td><td>{r.customers?.name||"—"}</td><td>{r.cafe_tables?.name||"—"}</td><td>{r.party_size}</td><td><select value={r.status} onChange={e=>changeStatus(r.id,e.target.value)}>{statuses.map(s=><option key={s[0]} value={s[0]}>{s[1]}</option>)}</select></td><td>{r.notes||"—"}</td></tr>)}</tbody>
      </table>
    </div>
  </div>
}