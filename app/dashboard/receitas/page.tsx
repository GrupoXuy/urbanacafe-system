"use client";
import {FormEvent,useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

type Product={id:string;name:string;unit:string;is_stock_item:boolean;active:boolean};
type RecipeItem={id:string;ingredient_product_id:string;quantity:number};
type Recipe={id:string;product_id:string;yield_quantity:number;active:boolean};

export default function Receitas(){
  const [business,setBusiness]=useState("");
  const [products,setProducts]=useState<Product[]>([]);
  const [recipes,setRecipes]=useState<Recipe[]>([]);
  const [items,setItems]=useState<RecipeItem[]>([]);
  const [editing,setEditing]=useState<string|null>(null);
  const [productId,setProductId]=useState("");
  const [yieldQty,setYieldQty]=useState("1");
  const [lines,setLines]=useState<{ingredient_product_id:string;quantity:string}[]>([{ingredient_product_id:"",quantity:""}]);
  const [saving,setSaving]=useState(false);
  const [message,setMessage]=useState("");

  async function load(){
    setMessage("");
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user)return;
    const {data:m,error:me}=await c.from("business_memberships")
      .select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(me||!m){setMessage(me?.message||"Negócio não encontrado");return}
    setBusiness(m.business_id);
    const [{data:p},{data:r},{data:i}]=await Promise.all([
      c.from("products").select("id,name,unit,is_stock_item,active").eq("business_id",m.business_id).eq("active",true).order("name"),
      c.from("recipes").select("id,product_id,yield_quantity,active").eq("business_id",m.business_id).order("active",{ascending:false}),
      c.from("recipe_items").select("id,recipe_id,ingredient_product_id,quantity")
    ]);
    setProducts((p||[]) as Product[]);
    setRecipes((r||[]) as Recipe[]);
    setItems((i||[]) as (RecipeItem&{recipe_id:string})[]);
  }

  useEffect(()=>{load()},[]);

  const ingredientProducts=useMemo(()=>products.filter(p=>p.is_stock_item),[products]);

  function reset(){
    setEditing(null);
    setProductId("");
    setYieldQty("1");
    setLines([{ingredient_product_id:"",quantity:""}]);
  }

  function edit(recipe:Recipe){
    setEditing(recipe.id);
    setProductId(recipe.product_id);
    setYieldQty(String(recipe.yield_quantity));
    const current=items.filter(i=>i.recipe_id===recipe.id);
    setLines(current.length
      ? current.map(i=>({ingredient_product_id:i.ingredient_product_id,quantity:String(i.quantity)}))
      : [{ingredient_product_id:"",quantity:""}]);
    window.scrollTo({top:0,behavior:"smooth"});
  }

  function addLine(){setLines(old=>[...old,{ingredient_product_id:"",quantity:""}])}
  function removeLine(index:number){setLines(old=>old.length===1?old:old.filter((_,i)=>i!==index))}

  async function save(e:FormEvent){
    e.preventDefault();
    setSaving(true);setMessage("");
    const valid=lines.every(l=>l.ingredient_product_id&&Number.isFinite(Number(l.quantity))&&Number(l.quantity)>0)
      &&new Set(lines.map(l=>l.ingredient_product_id)).size===lines.length
      &&Number(yieldQty)>0;
    if(!productId||!valid){
      setMessage("Preencha produto acabado, rendimento e ingredientes sem repetição.");
      setSaving(false);
      return;
    }
    const {error}=await createClient().rpc("save_recipe_transaction",{
      p_business_id:business,
      p_recipe_id:editing,
      p_product_id:productId,
      p_yield_quantity:Number(yieldQty),
      p_items:lines.map(l=>({ingredient_product_id:l.ingredient_product_id,quantity:Number(l.quantity)}))
    });
    if(error)setMessage(error.message);
    else{setMessage(editing?"Ficha técnica atualizada.":"Ficha técnica cadastrada.");reset();await load()}
    setSaving(false);
  }

  async function toggle(recipe:Recipe){
    const {error}=await createClient().from("recipes")
      .update({active:!recipe.active}).eq("id",recipe.id).eq("business_id",business);
    if(error)setMessage(error.message);else await load();
  }

  return <div className="main">
    <div className="topbar">
      <div><h1 className="title">Fichas técnicas</h1><p className="subtitle">Ingredientes, rendimento e consumo automático no POS</p></div>
      <Link href="/dashboard" className="btn" style={{width:"auto",textDecoration:"none"}}>Dashboard</Link>
    </div>

    <form className="card section" onSubmit={save}>
      <h2>{editing?"Editar ficha técnica":"Nova ficha técnica"}</h2>
      <div className="grid" style={{gridTemplateColumns:"2fr 1fr"}}>
        <label className="field"><span>Produto acabado</span><select value={productId} onChange={e=>setProductId(e.target.value)} required>
          <option value="">Selecione...</option>
          {products.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}
        </select></label>
        <label className="field"><span>Rendimento</span><input type="number" min="0.001" step="0.001" value={yieldQty} onChange={e=>setYieldQty(e.target.value)} required/></label>
      </div>

      <div className="section"><h2>Ingredientes</h2>
        {lines.map((line,index)=><div key={index} style={{display:"grid",gridTemplateColumns:"2fr 1fr auto",gap:10,alignItems:"end"}}>
          <label className="field"><span>Ingrediente</span><select value={line.ingredient_product_id} onChange={e=>setLines(old=>old.map((l,i)=>i===index?{...l,ingredient_product_id:e.target.value}:l))}>
            <option value="">Selecione...</option>
            {ingredientProducts.map(p=><option key={p.id} value={p.id}>{p.name} — {p.unit}</option>)}
          </select></label>
          <label className="field"><span>Quantidade</span><input type="number" min="0.001" step="0.001" value={line.quantity} onChange={e=>setLines(old=>old.map((l,i)=>i===index?{...l,quantity:e.target.value}:l))}/></label>
          <button type="button" onClick={()=>removeLine(index)} disabled={lines.length===1} style={{marginBottom:16}}>Remover</button>
        </div>)}
        <button type="button" onClick={addLine}>Adicionar ingrediente</button>
      </div>

      <div style={{display:"flex",gap:10,marginTop:18}}>
        <button className="btn" style={{width:"auto"}} disabled={!business||saving}>{saving?"Salvando...":editing?"Salvar alterações":"Cadastrar ficha"}</button>
        {editing&&<button type="button" className="btn" style={{width:"auto",background:"#666"}} onClick={reset}>Cancelar</button>}
      </div>
      {message&&<div className="notice">{message}</div>}
    </form>

    <div className="section">
      <h2>Fichas cadastradas</h2>
      <table className="table">
        <thead><tr><th>Produto</th><th>Rendimento</th><th>Ingredientes</th><th>Status</th><th></th></tr></thead>
        <tbody>
          {recipes.map(recipe=>{
            const product=products.find(p=>p.id===recipe.product_id);
            const current=items.filter(i=>i.recipe_id===recipe.id);
            return <tr key={recipe.id}>
              <td><b>{product?.name||"Produto"}</b></td>
              <td>{Number(recipe.yield_quantity).toFixed(3)}</td>
              <td>{current.length?current.map(i=>{
                const ingredient=products.find(p=>p.id===i.ingredient_product_id);
                return <div key={i.id}>{ingredient?.name||"Ingrediente"} — {Number(i.quantity).toFixed(3)} {ingredient?.unit||""}</div>
              }):"—"}</td>
              <td>{recipe.active?"Ativa":"Inativa"}</td>
              <td><div style={{display:"flex",gap:8}}><button onClick={()=>edit(recipe)}>Editar</button><button onClick={()=>toggle(recipe)}>{recipe.active?"Desativar":"Ativar"}</button></div></td>
            </tr>
          })}
          {!recipes.length&&<tr><td colSpan={5}>Nenhuma ficha técnica cadastrada.</td></tr>}
        </tbody>
      </table>
    </div>
  </div>
}
