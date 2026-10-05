"use client";
import {FormEvent,useEffect,useMemo,useState} from "react";
import {createClient} from "@/lib/supabase-browser";

type Product={
  id:string;
  name:string;
  unit:string;
  stock_quantity:number;
  min_stock:number;
  average_cost:number;
  sale_price:number;
  is_stock_item:boolean;
  is_sellable:boolean;
};

type Movement={
  id:string;
  product_id:string;
  movement_type:string;
  quantity:number;
  unit_cost:number;
  note:string|null;
  created_at:string;
};

const movementLabel:Record<string,string>={
  purchase:"Compra",
  sale:"Venda",
  adjustment:"Ajuste",
  waste:"Perda / descarte",
  transfer_in:"Transferência de entrada",
  transfer_out:"Transferência de saída",
  production:"Produção"
};

const money=(value:number)=>"UYU "+Number(value||0).toFixed(2);

export default function Estoque(){
  const [products,setProducts]=useState<Product[]>([]);
  const [movements,setMovements]=useState<Movement[]>([]);
  const [loading,setLoading]=useState(true);
  const [saving,setSaving]=useState(false);
  const [business,setBusiness]=useState("");
  const [role,setRole]=useState("");
  const [message,setMessage]=useState("");

  const [movementProduct,setMovementProduct]=useState("");
  const [movementKind,setMovementKind]=useState<"increase"|"decrease"|"waste">("increase");
  const [movementQuantity,setMovementQuantity]=useState("");
  const [movementNote,setMovementNote]=useState("");

  const [countProduct,setCountProduct]=useState("");
  const [countQuantity,setCountQuantity]=useState("");
  const [countNote,setCountNote]=useState("");

  const canManage=["owner","manager","stockkeeper"].includes(role);

  async function load(){
    setLoading(true);
    setMessage("");
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user){setLoading(false);return}

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

    setBusiness(membership.business_id);
    setRole(String(membership.role||""));

    const [{data:p,error:productsError},{data:m,error:movementError}]=await Promise.all([
      c.from("products")
        .select("id,name,unit,stock_quantity,min_stock,average_cost,sale_price,is_stock_item,is_sellable")
        .eq("business_id",membership.business_id)
        .eq("active",true)
        .eq("is_stock_item",true)
        .order("name"),
      c.from("stock_movements")
        .select("id,product_id,movement_type,quantity,unit_cost,note,created_at")
        .eq("business_id",membership.business_id)
        .order("created_at",{ascending:false})
        .limit(40)
    ]);

    if(productsError||movementError){
      setMessage(productsError?.message||movementError?.message||"Não foi possível carregar o estoque.");
    }

    const nextProducts=(p||[]) as Product[];
    setProducts(nextProducts);
    setMovements((m||[]) as Movement[]);
    if(!movementProduct&&nextProducts[0])setMovementProduct(nextProducts[0].id);
    if(!countProduct&&nextProducts[0])setCountProduct(nextProducts[0].id);
    setLoading(false);
  }

  useEffect(()=>{load()},[]);

  const totals=useMemo(()=>({
    items:products.length,
    low:products.filter(p=>Number(p.stock_quantity)<=Number(p.min_stock)).length,
    out:products.filter(p=>Number(p.stock_quantity)<=0).length,
    value:products.reduce((sum,p)=>sum+Number(p.stock_quantity||0)*Number(p.average_cost||0),0)
  }),[products]);

  async function submitMovement(e:FormEvent){
    e.preventDefault();
    setMessage("");
    const quantity=Number(movementQuantity);
    if(!business||!movementProduct||!Number.isFinite(quantity)||quantity<=0){
      setMessage("Informe o produto e uma quantidade maior que zero.");
      return;
    }

    setSaving(true);
    const c=createClient();
    const result=movementKind==="waste"
      ? await c.rpc("record_stock_waste",{
          p_product_id:movementProduct,
          p_quantity:quantity,
          p_note:movementNote.trim()||null
        })
      : await c.rpc("record_stock_adjustment",{
          p_product_id:movementProduct,
          p_delta:movementKind==="increase"?quantity:-quantity,
          p_note:movementNote.trim()||null
        });

    if(result.error){
      setMessage(result.error.message);
    }else{
      setMessage(movementKind==="waste"?"Perda registrada.":"Ajuste de estoque registrado.");
      setMovementQuantity("");
      setMovementNote("");
      await load();
    }
    setSaving(false);
  }

  async function submitCount(e:FormEvent){
    e.preventDefault();
    setMessage("");
    const quantity=Number(countQuantity);
    if(!business||!countProduct||!Number.isFinite(quantity)||quantity<0){
      setMessage("Informe o produto e uma contagem válida.");
      return;
    }

    setSaving(true);
    const {error}=await createClient().rpc("set_stock_count",{
      p_product_id:countProduct,
      p_counted_quantity:quantity,
      p_note:countNote.trim()||null
    });

    if(error){
      setMessage(error.message);
    }else{
      setMessage("Inventário físico processado.");
      setCountQuantity("");
      setCountNote("");
      await load();
    }
    setSaving(false);
  }

  function selectCount(product:Product){
    setCountProduct(product.id);
    setCountQuantity(String(Number(product.stock_quantity)));
    window.scrollTo({top:0,behavior:"smooth"});
  }

  const productName=(id:string)=>products.find(p=>p.id===id)?.name||"Produto";

  return <div className="main">
    <div className="topbar">
      <div>
        <h1 className="title">Estoque</h1>
        <p className="subtitle">Saldo, entradas, perdas e inventário físico com histórico transacional</p>
      </div>
    </div>

    {message&&<div className="notice">{message}</div>}

    <div className="grid section">
      <div className="card"><div className="label">Itens controlados</div><div className="value">{totals.items}</div></div>
      <div className="card"><div className="label">Abaixo do mínimo</div><div className="value">{totals.low}</div></div>
      <div className="card"><div className="label">Sem estoque</div><div className="value">{totals.out}</div></div>
      <div className="card"><div className="label">Valor do estoque</div><div className="value">{money(totals.value)}</div></div>
    </div>

    {canManage&&<div className="grid section" style={{alignItems:"start"}}>
      <form className="card" onSubmit={submitMovement}>
        <h2>Movimentar estoque</h2>
        <p className="subtitle">O saldo e o ledger são atualizados na mesma transação.</p>
        <div className="grid" style={{gridTemplateColumns:"repeat(2,minmax(0,1fr))"}}>
          <label className="field">
            <span>Produto</span>
            <select value={movementProduct} onChange={e=>setMovementProduct(e.target.value)} required>
              <option value="">Selecione</option>
              {products.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </label>
          <label className="field">
            <span>Operação</span>
            <select value={movementKind} onChange={e=>setMovementKind(e.target.value as typeof movementKind)}>
              <option value="increase">Ajuste — entrada</option>
              <option value="decrease">Ajuste — saída</option>
              <option value="waste">Perda / descarte</option>
            </select>
          </label>
        </div>
        <label className="field"><span>Quantidade</span><input type="number" min="0.001" step="0.001" value={movementQuantity} onChange={e=>setMovementQuantity(e.target.value)} required/></label>
        <label className="field"><span>Observação</span><input value={movementNote} onChange={e=>setMovementNote(e.target.value)} placeholder="Motivo do movimento"/></label>
        <button className="btn" disabled={saving}>{saving?"Processando...":"Registrar movimento"}</button>
      </form>

      <form className="card" onSubmit={submitCount}>
        <h2>Inventário físico</h2>
        <p className="subtitle">Informe a quantidade realmente encontrada; a diferença vira ajuste compensatório.</p>
        <label className="field">
          <span>Produto</span>
          <select value={countProduct} onChange={e=>setCountProduct(e.target.value)} required>
            <option value="">Selecione</option>
            {products.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </label>
        <label className="field"><span>Quantidade contada</span><input type="number" min="0" step="0.001" value={countQuantity} onChange={e=>setCountQuantity(e.target.value)} required/></label>
        <label className="field"><span>Observação</span><input value={countNote} onChange={e=>setCountNote(e.target.value)} placeholder="Ex.: conferência de fechamento"/></label>
        <button className="btn" disabled={saving}>{saving?"Processando...":"Registrar contagem"}</button>
      </form>
    </div>}

    {!canManage&&!loading&&<div className="notice">Seu perfil está em modo de consulta. Apenas Proprietário, Gerente e Estoque podem movimentar o inventário.</div>}

    <div className="section">
      <h2>Saldo atual</h2>
      {loading?<div className="card">Carregando estoque...</div>:
      <div className="card" style={{overflowX:"auto"}}>
        <table className="table">
          <thead><tr><th>Produto</th><th>Un.</th><th>Saldo</th><th>Mínimo</th><th>Custo médio</th><th>Valor</th><th>Status</th><th></th></tr></thead>
          <tbody>
            {products.map(p=><tr key={p.id}>
              <td><b>{p.name}</b></td>
              <td>{p.unit}</td>
              <td>{Number(p.stock_quantity).toFixed(3)}</td>
              <td>{Number(p.min_stock).toFixed(3)}</td>
              <td>{money(Number(p.average_cost))}</td>
              <td>{money(Number(p.stock_quantity)*Number(p.average_cost))}</td>
              <td>{Number(p.stock_quantity)<=0?"Sem estoque":Number(p.stock_quantity)<=Number(p.min_stock)?"Reposição":"Normal"}</td>
              <td>{canManage&&<button type="button" onClick={()=>selectCount(p)}>Contar</button>}</td>
            </tr>)}
            {!products.length&&<tr><td colSpan={8}>Nenhum item com controle de estoque cadastrado.</td></tr>}
          </tbody>
        </table>
      </div>}
    </div>

    <div className="section">
      <h2>Últimos movimentos</h2>
      {loading?<div className="card">Carregando histórico...</div>:
      <div className="card" style={{overflowX:"auto"}}>
        <table className="table">
          <thead><tr><th>Data</th><th>Produto</th><th>Tipo</th><th>Quantidade</th><th>Custo</th><th>Observação</th></tr></thead>
          <tbody>
            {movements.length?movements.map(m=><tr key={m.id}>
              <td>{new Date(m.created_at).toLocaleString("pt-BR")}</td>
              <td>{productName(m.product_id)}</td>
              <td>{movementLabel[m.movement_type]||m.movement_type}</td>
              <td>{Number(m.quantity).toFixed(3)}</td>
              <td>{money(Number(m.unit_cost))}</td>
              <td>{m.note||"—"}</td>
            </tr>):<tr><td colSpan={6}>Nenhum movimento registrado.</td></tr>}
          </tbody>
        </table>
      </div>}
    </div>
  </div>;
}
