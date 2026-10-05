"use client";
import {FormEvent,useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

type Business={
  id:string;
  name:string;
  legal_name:string|null;
  currency:string;
  timezone:string;
  active:boolean;
};

const timezones=[
  "America/Montevideo",
  "America/Sao_Paulo",
  "America/Argentina/Buenos_Aires",
  "America/New_York",
  "America/Los_Angeles",
  "UTC"
];

export default function Configuracoes(){
  const [business,setBusiness]=useState<Business|null>(null);
  const [role,setRole]=useState("");
  const [name,setName]=useState("");
  const [legalName,setLegalName]=useState("");
  const [currency,setCurrency]=useState("UYU");
  const [timezone,setTimezone]=useState("America/Montevideo");
  const [loading,setLoading]=useState(true);
  const [saving,setSaving]=useState(false);
  const [message,setMessage]=useState("");

  const canEdit=role==="owner"||role==="manager";

  async function load(){
    setLoading(true);
    setMessage("");
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user){
      setLoading(false);
      return;
    }

    const {data:membership,error:membershipError}=await c
      .from("business_memberships")
      .select("business_id,role")
      .eq("user_id",user.id)
      .eq("active",true)
      .limit(1)
      .maybeSingle();

    if(membershipError||!membership){
      setMessage(membershipError?.message||"Negócio não encontrado.");
      setLoading(false);
      return;
    }

    const {data:businessRow,error:businessError}=await c
      .from("businesses")
      .select("id,name,legal_name,currency,timezone,active")
      .eq("id",membership.business_id)
      .maybeSingle();

    if(businessError||!businessRow){
      setMessage(businessError?.message||"Não foi possível carregar as configurações.");
      setLoading(false);
      return;
    }

    const b=businessRow as Business;
    setBusiness(b);
    setRole(String(membership.role||""));
    setName(b.name);
    setLegalName(b.legal_name||"");
    setCurrency(b.currency||"UYU");
    setTimezone(b.timezone||"America/Montevideo");
    setLoading(false);
  }

  useEffect(()=>{load()},[]);

  async function save(e:FormEvent){
    e.preventDefault();
    setSaving(true);
    setMessage("");

    if(!business){
      setMessage("Negócio não carregado.");
      setSaving(false);
      return;
    }

    const {data,error}=await createClient().rpc("update_business_settings",{
      p_business_id:business.id,
      p_name:name.trim(),
      p_legal_name:legalName.trim()||null,
      p_currency:currency.trim().toUpperCase(),
      p_timezone:timezone
    });

    if(error){
      setMessage(error.message);
    }else{
      const b=data as Business;
      setBusiness(b);
      setName(b.name);
      setLegalName(b.legal_name||"");
      setCurrency(b.currency);
      setTimezone(b.timezone);
      setMessage("Configurações salvas.");
    }
    setSaving(false);
  }

  if(loading)return <div className="main"><div className="card">Carregando configurações...</div></div>;

  return <div className="main">
    <div className="topbar">
      <div>
        <h1 className="title">Configurações</h1>
        <p className="subtitle">Dados e parâmetros principais da operação</p>
      </div>
      <Link href="/dashboard" className="btn" style={{width:"auto",textDecoration:"none"}}>Dashboard</Link>
    </div>

    {message&&<div className="notice">{message}</div>}

    {!business ? <div className="card">Não foi possível identificar o negócio ativo.</div> :
      <form className="card" onSubmit={save}>
        <h2>Negócio</h2>
        <p className="subtitle">Esses dados alimentam os relatórios e a operação diária.</p>

        <label className="field">
          <span>Nome comercial</span>
          <input value={name} onChange={e=>setName(e.target.value)} disabled={!canEdit} required maxLength={120}/>
        </label>

        <label className="field">
          <span>Razão social</span>
          <input value={legalName} onChange={e=>setLegalName(e.target.value)} disabled={!canEdit} maxLength={160}/>
        </label>

        <div className="grid" style={{gridTemplateColumns:"repeat(2,minmax(0,1fr))"}}>
          <label className="field">
            <span>Moeda</span>
            <input value={currency} onChange={e=>setCurrency(e.target.value)} disabled={!canEdit} maxLength={3} minLength={3} placeholder="UYU" required/>
          </label>
          <label className="field">
            <span>Fuso horário</span>
            <select value={timezone} onChange={e=>setTimezone(e.target.value)} disabled={!canEdit}>
              {timezones.map(t=><option key={t} value={t}>{t}</option>)}
            </select>
          </label>
        </div>

        <div className="notice">
          Status: {business.active?"Ativo":"Inativo"} · Seu cargo: {role||"consulta"}
        </div>

        {canEdit
          ? <button className="btn" disabled={saving}>{saving?"Salvando...":"Salvar configurações"}</button>
          : <div className="notice">Somente Proprietário e Gerente podem alterar as configurações do negócio.</div>}
      </form>
    }
  </div>;
}
