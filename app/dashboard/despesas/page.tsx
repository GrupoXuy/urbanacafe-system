"use client";
import {useEffect,useState} from "react";
import {createClient} from "@/lib/supabase-browser";

export default function Despesas(){
 const [business,setBusiness]=useState(""),[description,setDescription]=useState(""),[amount,setAmount]=useState(""),[category,setCategory]=useState(""),[paymentMethod,setPaymentMethod]=useState("cash"),[message,setMessage]=useState(""),[items,setItems]=useState<any[]>([]);
 async function load(){const c=createClient();const {data:{user}}=await c.auth.getUser();if(!user)return;const {data:m}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();if(m){setBusiness(m.business_id);const {data}=await c.from("expenses").select("*").eq("business_id",m.business_id).order("expense_date",{ascending:false}).limit(30);setItems(data||[])}}
 useEffect(()=>{load()},[]);
 async function save(){
   setMessage("");
   const {error}=await createClient().rpc("record_expense",{p_business_id:business,p_description:description,p_category:category,p_amount:Number(amount),p_expense_date:new Date().toISOString().slice(0,10),p_payment_method:paymentMethod});
   if(error)setMessage(error.message);
   else{setMessage(paymentMethod==="cash"?"Despesa registrada e abatida do caixa.":"Despesa registrada.");setDescription("");setAmount("");setCategory("");load()}
 }
 return <div className="main"><h1 className="title">Despesas</h1><p className="subtitle">Lançamentos operacionais com controle de pagamento</p>
 <div className="card section"><div className="grid">
 <label className="field"><span>Descrição</span><input value={description} onChange={e=>setDescription(e.target.value)} placeholder="Ex.: energia elétrica"/></label>
 <label className="field"><span>Categoria</span><input value={category} onChange={e=>setCategory(e.target.value)} placeholder="Ex.: utilidades"/></label>
 <label className="field"><span>Valor UYU</span><input type="number" min="0.01" step="0.01" value={amount} onChange={e=>setAmount(e.target.value)}/></label>
 <label className="field"><span>Pagamento</span><select value={paymentMethod} onChange={e=>setPaymentMethod(e.target.value)}><option value="cash">Dinheiro</option><option value="debit">Débito</option><option value="credit">Crédito</option><option value="transfer">Transferência</option><option value="mercado_pago">Mercado Pago</option><option value="other">Outro</option></select></label>
 </div><button className="btn" onClick={save} disabled={!business||!description||Number(amount)<=0}>Registrar despesa</button>{message&&<div className="notice">{message}</div>}</div>
 <div className="section"><table className="table"><thead><tr><th>Data</th><th>Descrição</th><th>Categoria</th><th>Pagamento</th><th>Valor</th></tr></thead><tbody>{items.map(x=><tr key={x.id}><td>{x.expense_date}</td><td>{x.description}</td><td>{x.category||"—"}</td><td>{x.payment_method}</td><td>UYU {Number(x.amount).toFixed(2)}</td></tr>)}</tbody></table></div></div>
}