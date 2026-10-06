"use client";
import {FormEvent,useEffect,useState} from "react";
import Link from "next/link";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase-browser";

export default function ResetPassword(){
  const router=useRouter();
  const [password,setPassword]=useState(""),[confirmation,setConfirmation]=useState(""),[message,setMessage]=useState(""),[ready,setReady]=useState(false),[saving,setSaving]=useState(false);
  useEffect(()=>{createClient().auth.getUser().then(({data,error})=>{
    if(error||!data.user)setMessage("Link de recuperação inválido ou expirado.");else setReady(true);
  })},[]);
  async function submit(e:FormEvent){
    e.preventDefault();
    if(password.length<8){setMessage("A senha deve ter pelo menos 8 caracteres.");return}
    if(password!==confirmation){setMessage("As senhas não coincidem.");return}
    setSaving(true);setMessage("");
    const {error}=await createClient().auth.updateUser({password});
    if(error)setMessage(error.message);
    else{setMessage("Senha alterada com sucesso. Você será redirecionado para o login.");setTimeout(()=>router.push("/login"),1200)}
    setSaving(false);
  }
  return <main className="login"><form className="login-card" onSubmit={submit}>
    <h1>Nova senha</h1><p>Defina uma nova senha para o seu acesso.</p>{message&&<div className="notice">{message}</div>}
    {ready&&<><label className="field"><span>Nova senha</span><input type="password" value={password} onChange={e=>setPassword(e.target.value)} minLength={8} required /></label>
    <label className="field"><span>Confirmar senha</span><input type="password" value={confirmation} onChange={e=>setConfirmation(e.target.value)} minLength={8} required /></label>
    <button className="btn" disabled={saving}>{saving?"Salvando...":"Alterar senha"}</button></>}
    {!ready&&<Link href="/login" className="btn" style={{display:"block",textAlign:"center",textDecoration:"none",marginTop:16}}>Voltar para entrar</Link>}
  </form></main>;
}
