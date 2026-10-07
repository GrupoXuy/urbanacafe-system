"use client";
import {FormEvent,useEffect,useState} from "react";
import {createClient} from "@/lib/supabase-browser";

type Product={id:string;category_id:string|null;name:string;sku:string|null;unit:string;sale_price:number;average_cost:number;stock_quantity:number;min_stock:number;is_stock_item:boolean;is_sellable:boolean;active:boolean;production_station:"none"|"kitchen"|"bar"};
type Category={id:string;name:string};

export default function Produtos(){
  const [business,setBusiness]=useState("");
  const [role,setRole]=useState("");
  const [products,setProducts]=useState<Product[]>([]);
  const [categories,setCategories]=useState<Category[]>([]);
  const [editing,setEditing]=useState<string|null>(null);
  const [name,setName]=useState("");
  const [sku,setSku]=useState("");
  const [category,setCategory]=useState("");
  const [unit,setUnit]=useState("UN");
  const [price,setPrice]=useState("");
  const [cost,setCost]=useState("");
  const [minStock,setMinStock]=useState("0");
  const [stockItem,setStockItem]=useState(true);
  const [sellable,setSellable]=useState(true);
  const [productionStation,setProductionStation]=useState<"none"|"kitchen"|"bar">("kitchen");
  const [message,setMessage]=useState("");
  const [saving,setSaving]=useState(false);
  const [deleting,setDeleting]=useState<string|null>(null);

  async function load(){
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user)return;
    const {data:m}=await c.from("business_memberships").select("business_id,role").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(!m)return;
    setBusiness(m.business_id);
    setRole(String(m.role||""));
    const [{data:p},{data:cats}]=await Promise.all([
      c.from("products").select("id,category_id,name,sku,unit,sale_price,average_cost,stock_quantity,min_stock,is_stock_item,is_sellable,active,production_station").eq("business_id",m.business_id).order("name"),
      c.from("categories").select("id,name").eq("business_id",m.business_id).eq("active",true).order("name")
    ]);
    setProducts((p||[]) as Product[]);setCategories((cats||[]) as Category[]);
  }
  useEffect(()=>{load()},[]);

  const canManage=role==="owner"||role==="manager";

  function reset(){
    setEditing(null);setName("");setSku("");setCategory("");setUnit("UN");setPrice("");setCost("");setMinStock("0");setStockItem(true);setSellable(true);setProductionStation("kitchen");
  }
  function edit(p:Product){
    setEditing(p.id);setName(p.name);setSku(p.sku||"");setCategory(p.category_id||"");setUnit(p.unit);setPrice(String(p.sale_price));setCost(String(p.average_cost));setMinStock(String(p.min_stock));setStockItem(p.is_stock_item);setSellable(p.is_sellable);setProductionStation(p.production_station||"none");
    window.scrollTo({top:0,behavior:"smooth"});
  }
  async function save(e:FormEvent){
    e.preventDefault();setSaving(true);setMessage("");
    const c=createClient();
    const payload={business_id:business,name:name.trim(),sku:sku.trim()||null,category_id:category||null,unit:unit.trim()||"UN",sale_price:Number(price||0),average_cost:Number(cost||0),min_stock:Number(minStock||0),is_stock_item:stockItem,is_sellable:sellable,production_station:productionStation,active:true};
    const result=editing
      ? await c.from("products").update(payload).eq("id",editing).eq("business_id",business)
      : await c.from("products").insert(payload);
    if(result.error)setMessage(result.error.message);
    else{setMessage(editing?"Produto atualizado.":"Produto cadastrado.");reset();await load()}
    setSaving(false);
  }
  async function toggle(p:Product){
    const {error}=await createClient().from("products").update({active:!p.active}).eq("id",p.id).eq("business_id",business);
    if(error)setMessage(error.message);else load();
  }

  async function removeProduct(p:Product){
    const confirmed=window.confirm(
      `¿Eliminar el producto "${p.name}" definitivamente? Esta acción no se puede deshacer. Si el producto tiene ventas, compras o movimientos históricos asociados, el sistema bloqueará la eliminación para proteger la integridad de los registros.`
    );
    if(!confirmed)return;

    setDeleting(p.id);
    setMessage("");
    try{
      const {error}=await createClient()
        .from("products")
        .delete()
        .eq("id",p.id)
        .eq("business_id",business);

      if(error){
        if(error.code==="23503"){
          setMessage(`No se puede eliminar "${p.name}" porque tiene registros históricos asociados. Desactívalo para mantener el historial.`);
        }else if(error.code==="42501"){
          setMessage("No tienes permisos para eliminar este producto.");
        }else{
          setMessage("No se pudo eliminar el producto.");
        }
        return;
      }

      if(editing===p.id)reset();
      setMessage(`Producto "${p.name}" eliminado.`);
      await load();
    }finally{
      setDeleting(null);
    }
  }

  return <div className="main">
    <div className="topbar"><div><h1 className="title">Produtos</h1><p className="subtitle">Catálogo, preços, custos e parâmetros de estoque</p></div></div>
    {canManage ? <>
    <form className="card section" onSubmit={save}>
      <h2>{editing?"Editar produto":"Novo produto"}</h2>
      <div className="grid" style={{gridTemplateColumns:"repeat(4,minmax(0,1fr))"}}>
        <label className="field"><span>Nome</span><input value={name} onChange={e=>setName(e.target.value)} required/></label>
        <label className="field"><span>SKU</span><input value={sku} onChange={e=>setSku(e.target.value)} placeholder="Opcional"/></label>
        <label className="field"><span>Categoria</span><select value={category} onChange={e=>setCategory(e.target.value)}><option value="">Sem categoria</option>{categories.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
        <label className="field"><span>Unidade</span><input value={unit} onChange={e=>setUnit(e.target.value)} placeholder="UN, KG, L..."/></label>
      </div>
      <div className="grid" style={{gridTemplateColumns:"repeat(4,minmax(0,1fr))"}}>
        <label className="field"><span>Preço de venda</span><input type="number" min="0" step="0.01" value={price} onChange={e=>setPrice(e.target.value)} required/></label>
        <label className="field"><span>Custo médio</span><input type="number" min="0" step="0.0001" value={cost} onChange={e=>setCost(e.target.value)}/></label>
        <label className="field"><span>Estoque mínimo</span><input type="number" min="0" step="0.001" value={minStock} onChange={e=>setMinStock(e.target.value)}/></label>
        <div className="field"><span>Operação</span><label><input type="checkbox" checked={stockItem} onChange={e=>setStockItem(e.target.checked)}/> Controla estoque</label><label><input type="checkbox" checked={sellable} onChange={e=>setSellable(e.target.checked)}/> Vendável</label><label>Produção<select value={productionStation} onChange={e=>setProductionStation(e.target.value as "none"|"kitchen"|"bar")}><option value="kitchen">Cozinha</option><option value="bar">Bar</option><option value="none">Sem produção</option></select></label></div>
      </div>
      <div style={{display:"flex",gap:10}}><button className="btn" style={{width:"auto"}} disabled={!business||saving}>{saving?"Salvando...":editing?"Salvar alterações":"Cadastrar produto"}</button>{editing&&<button type="button" className="btn" style={{width:"auto",background:"#666"}} onClick={reset}>Cancelar</button>}</div>
      {message&&<div className="notice">{message}</div>}
    </form>

    </> : <div className="notice section">Modo de consulta: solo Propietario y Gerente pueden crear, editar, activar, desactivar o eliminar productos.</div>}
    <div className="section"><table className="table"><thead><tr><th>Produto</th><th>Categoria</th><th>Preço</th><th>Custo</th><th>Estoque</th><th>Produção</th><th>Status</th><th></th></tr></thead><tbody>
      {products.map(p=><tr key={p.id}><td><b>{p.name}</b>{p.sku&&<div className="subtitle">{p.sku}</div>}</td><td>{categories.find(c=>c.id===p.category_id)?.name||"—"}</td><td>UYU {Number(p.sale_price).toFixed(2)}</td><td>UYU {Number(p.average_cost).toFixed(4)}</td><td>{p.stock_quantity} {p.unit}</td><td>{p.production_station==="kitchen"?"Cozinha":p.production_station==="bar"?"Bar":"Sem produção"}</td><td>{!p.active?"Inativo":Number(p.stock_quantity)<=Number(p.min_stock)?"Reposição":"Ativo"}</td><td>{canManage&&<div style={{display:"flex",gap:8,flexWrap:"wrap"}}>
        <button onClick={()=>edit(p)} disabled={deleting===p.id}>Editar</button>
        <button onClick={()=>toggle(p)} disabled={deleting===p.id}>{p.active?"Desactivar":"Activar"}</button>
        <button
          onClick={()=>removeProduct(p)}
          disabled={deleting===p.id}
          style={{background:"#b42318",color:"#fff"}}
        >
          {deleting===p.id?"Eliminando...":"Eliminar"}
        </button>
      </div>}</td></tr>)}
    </tbody></table></div>
  </div>
}