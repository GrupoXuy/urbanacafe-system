"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

type Product={
  id:string;
  name:string;
  sale_price:number;
  stock_quantity:number;
  is_stock_item:boolean;
};

type CartItem=Product&{quantity:number};
type Customer={id:string;name:string;phone:string|null};
type CafeTable={id:string;name:string;seats:number|null};
type OpenOrder={
  id:string;
  table_id:string|null;
  customer_id:string|null;
  subtotal:number;
  discount:number;
  total:number;
  notes:string|null;
  created_at:string;
  cafe_tables?:{name:string}|null;
  customers?:{name:string}|null;
};
type OrderLine={
  product_id:string;
  quantity:number;
  unit_price:number;
  products?:{name:string}|null;
};

const paymentMethods=[
  ["cash","Dinheiro"],
  ["debit","Débito"],
  ["credit","Crédito"],
  ["transfer","Transferência"],
  ["mercado_pago","Mercado Pago"],
  ["other","Outro"]
] as const;

const money=(value:number)=>"UYU "+Number(value||0).toFixed(2);

export default function Comandas(){
  const [business,setBusiness]=useState("");
  const [session,setSession]=useState<any>(null);
  const [products,setProducts]=useState<Product[]>([]);
  const [customers,setCustomers]=useState<Customer[]>([]);
  const [tables,setTables]=useState<CafeTable[]>([]);
  const [orders,setOrders]=useState<OpenOrder[]>([]);
  const [cart,setCart]=useState<CartItem[]>([]);
  const [search,setSearch]=useState("");
  const [customerId,setCustomerId]=useState("");
  const [tableId,setTableId]=useState("");
  const [note,setNote]=useState("");
  const [paymentMethod,setPaymentMethod]=useState("cash");
  const [editingId,setEditingId]=useState("");
  const [dirty,setDirty]=useState(false);
  const [message,setMessage]=useState("");
  const [loading,setLoading]=useState(true);
  const [saving,setSaving]=useState(false);

  async function loadBase(){
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user){setLoading(false);return}

    const {data:m,error:me}=await c.from("business_memberships")
      .select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();

    if(me||!m){
      setMessage(me?.message||"Negócio não encontrado");
      setLoading(false);
      return;
    }

    setBusiness(m.business_id);

    const [{data:s},{data:p},{data:cu},{data:t}]=await Promise.all([
      c.from("cash_sessions").select("id,opening_amount,opened_at,status")
        .eq("business_id",m.business_id).eq("status","open").maybeSingle(),
      c.from("products").select("id,name,sale_price,stock_quantity,is_stock_item")
        .eq("business_id",m.business_id).eq("active",true).eq("is_sellable",true).order("name"),
      c.from("customers").select("id,name,phone")
        .eq("business_id",m.business_id).eq("active",true).order("name"),
      c.from("cafe_tables").select("id,name,seats")
        .eq("business_id",m.business_id).eq("active",true).order("name")
    ]);

    setSession(s);
    setProducts((p||[]) as Product[]);
    setCustomers((cu||[]) as Customer[]);
    setTables((t||[]) as CafeTable[]);
    await loadOrders(m.business_id);
    setLoading(false);
  }

  async function loadOrders(targetBusiness=business){
    if(!targetBusiness)return;
    const c=createClient();
    const {data,error}=await c.from("sales")
      .select("id,table_id,customer_id,subtotal,discount,total,notes,created_at,cafe_tables(name),customers(name)")
      .eq("business_id",targetBusiness)
      .eq("status","open")
      .order("created_at",{ascending:true});

    if(error){
      setMessage(error.message);
      return;
    }

    setOrders((data||[]) as OpenOrder[]);
  }

  useEffect(()=>{loadBase()},[]);

  const filtered=useMemo(
    ()=>products.filter(p=>p.name.toLowerCase().includes(search.toLowerCase())),
    [products,search]
  );

  const total=useMemo(
    ()=>cart.reduce((sum,item)=>sum+Number(item.sale_price)*item.quantity,0),
    [cart]
  );

  const occupiedTables=new Set(orders.map(o=>o.table_id).filter(Boolean) as string[]);

  function resetEditor(){
    setEditingId("");
    setCart([]);
    setCustomerId("");
    setTableId("");
    setNote("");
    setPaymentMethod("cash");
    setDirty(false);
  }

  function add(p:Product){
    setCart(old=>{
      const current=old.find(i=>i.id===p.id);
      const quantity=(current?.quantity||0)+1;
      return current
        ? old.map(i=>i.id===p.id?{...i,quantity}:i)
        : [...old,{...p,quantity:1}];
    });
    setDirty(true);
  }

  function decrease(id:string){
    setCart(old=>old.map(i=>i.id===id?{...i,quantity:i.quantity-1}:i).filter(i=>i.quantity>0));
    setDirty(true);
  }

  function remove(id:string){
    setCart(old=>old.filter(i=>i.id!==id));
    setDirty(true);
  }

  async function openOrder(order:OpenOrder){
    setMessage("");
    const c=createClient();
    const {data,error}=await c.from("sale_items")
      .select("product_id,quantity,unit_price,products(name)")
      .eq("sale_id",order.id);

    if(error){
      setMessage(error.message);
      return;
    }

    setEditingId(order.id);
    setCustomerId(order.customer_id||"");
    setTableId(order.table_id||"");
    setNote(order.notes||"");
    setCart((data||[]).map((line:OrderLine)=>{
      const product=products.find(p=>p.id===line.product_id);
      return {
        id:line.product_id,
        name:line.products?.name||"Produto",
        sale_price:Number(line.unit_price||0),
        stock_quantity:Number(product?.stock_quantity||0),
        is_stock_item:Boolean(product?.is_stock_item),
        quantity:Number(line.quantity||0)
      };
    }));
    setDirty(false);
  }

  async function persistOrder():Promise<string|null>{
    if(!business||!cart.length){
      setMessage("Adicione pelo menos um produto.");
      return null;
    }

    setSaving(true);
    const c=createClient();
    const payload={
      p_customer_id:customerId||null,
      p_table_id:tableId||null,
      p_notes:note.trim()||null,
      p_items:cart.map(i=>({product_id:i.id,quantity:i.quantity})),
      p_discount:0
    };

    const result=editingId
      ? await c.rpc("update_open_order",{p_sale_id:editingId,...payload})
      : await c.rpc("create_open_order",{p_business_id:business,...payload});

    if(result.error){
      setMessage(result.error.message);
      setSaving(false);
      return null;
    }

    const id=(result.data as {id:string}).id;
    setEditingId(id);
    setDirty(false);
    await loadOrders();
    setMessage(editingId?"Comanda atualizada.":"Comanda aberta.");
    setSaving(false);
    return id;
  }

  async function saveOrder(){
    await persistOrder();
  }

  async function finalizeOrder(){
    setMessage("");
    if(!session){
      setMessage("Abra o caixa antes de finalizar uma comanda.");
      return;
    }

    let id=editingId;
    if(!id){
      id=await persistOrder();
      if(!id)return;
    }else if(dirty){
      id=await persistOrder();
      if(!id)return;
    }

    setSaving(true);
    const {error}=await createClient().rpc("close_open_order",{
      p_sale_id:id,
      p_cash_session_id:session.id,
      p_payment_method:paymentMethod
    });

    if(error){
      setMessage(error.message);
    }else{
      setMessage("Comanda finalizada. Pagamento, caixa e estoque foram processados.");
      resetEditor();
      await loadBase();
    }
    setSaving(false);
  }

  async function cancelOrder(){
    if(!editingId){
      resetEditor();
      setMessage("Rascunho descartado.");
      return;
    }

    const reason=window.prompt("Motivo do cancelamento da comanda:","Cliente desistiu");
    if(reason===null)return;

    setSaving(true);
    const {error}=await createClient().rpc("cancel_open_order",{
      p_sale_id:editingId,
      p_reason:reason.trim()||"Comanda cancelada"
    });

    if(error){
      setMessage(error.message);
    }else{
      setMessage("Comanda cancelada e mesa liberada.");
      resetEditor();
      await loadOrders();
    }
    setSaving(false);
  }

  const occupiedCount=occupiedTables.size;
  const pendingTotal=orders.reduce((sum,o)=>sum+Number(o.total||0),0);

  if(loading)return <main className="main"><p>Carregando comandas...</p></main>;

  return <main className="main">
    <div className="topbar">
      <div>
        <h1 className="title">Comandas</h1>
        <p className="subtitle">Atendimento de mesa, edição e fechamento no caixa</p>
      </div>
      <div style={{display:"flex",gap:10,alignItems:"center"}}>
        <span className={session?"positive":"negative"}>{session?"Caixa aberto":"Caixa fechado"}</span>
        <Link href="/dashboard/pos" className="btn" style={{width:"auto",textDecoration:"none"}}>POS imediato</Link>
      </div>
    </div>

    {!session&&<div className="notice">
      O caixa está fechado. Você pode preparar comandas, mas a finalização exige uma sessão aberta em <Link href="/dashboard/caixa">Caixa</Link>.
    </div>}

    {message&&<div className="notice">{message}</div>}

    <div className="grid">
      <div className="card"><div className="label">Comandas abertas</div><div className="value">{orders.length}</div></div>
      <div className="card"><div className="label">Mesas ocupadas</div><div className="value">{occupiedCount}</div></div>
      <div className="card"><div className="label">Total pendente</div><div className="value">{money(pendingTotal)}</div></div>
      <div className="card"><div className="label">Editor</div><div className="value">{editingId?"Em edição":"Nova"}</div></div>
    </div>

    <div className="section" style={{display:"grid",gridTemplateColumns:"minmax(0,1.1fr) minmax(360px,1.4fr)",gap:18}}>
      <section>
        <div className="card">
          <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:10}}>
            <div>
              <h2>Comandas abertas</h2>
              <p className="subtitle">Uma comanda aberta por mesa. O estoque só é baixado no fechamento.</p>
            </div>
            <button type="button" onClick={resetEditor} disabled={saving}>Nova</button>
          </div>

          <div style={{display:"grid",gap:10,marginTop:16}}>
            {orders.map(order=>{
              const tableName=order.cafe_tables?.name||"Balcão";
              const customerName=order.customers?.name||"Consumidor final";
              const selected=editingId===order.id;
              return <button
                type="button"
                key={order.id}
                onClick={()=>openOrder(order)}
                style={{
                  textAlign:"left",
                  padding:14,
                  border:"1px solid #e3e3df",
                  borderRadius:10,
                  background:selected?"#f4efe4":"#fff",
                  cursor:"pointer"
                }}
              >
                <div style={{display:"flex",justifyContent:"space-between",gap:12}}>
                  <b>{tableName}</b>
                  <b>{money(Number(order.total))}</b>
                </div>
                <div className="subtitle">{customerName} · aberta às {new Date(order.created_at).toLocaleTimeString("pt-BR",{hour:"2-digit",minute:"2-digit"})}</div>
                {order.notes&&<div style={{marginTop:6,fontSize:13}}>{order.notes}</div>}
              </button>;
            })}
            {!orders.length&&<div className="notice">Nenhuma comanda aberta. Crie a primeira ao lado.</div>}
          </div>
        </div>

        <div className="card section">
          <h2>Mapa rápido de mesas</h2>
          <div style={{display:"grid",gridTemplateColumns:"repeat(2,minmax(0,1fr))",gap:10}}>
            {tables.map(table=>{
              const occupied=occupiedTables.has(table.id);
              return <div key={table.id} style={{padding:12,border:"1px solid #eee",borderRadius:10}}>
                <b>{table.name}</b>
                <div className={occupied?"negative":"positive"} style={{marginTop:4}}>{occupied?"Ocupada":"Disponível"}</div>
                <div className="subtitle">{table.seats||"—"} lugares</div>
              </div>;
            })}
          </div>
          {!tables.length&&<p className="subtitle">Cadastre mesas em <Link href="/dashboard/mesas">Mesas</Link>.</p>}
        </div>
      </section>

      <section className="card">
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:10}}>
          <div>
            <h2>{editingId?"Editar comanda":"Nova comanda"}</h2>
            <p className="subtitle">Produtos ficam em aberto até o fechamento.</p>
          </div>
          {editingId&&<span className="positive">Salva</span>}
        </div>

        <div className="grid" style={{gridTemplateColumns:"1fr 1fr",gap:10}}>
          <label className="field"><span>Mesa</span><select value={tableId} onChange={e=>{setTableId(e.target.value);setDirty(true)}}>
            <option value="">Balcão / sem mesa</option>
            {tables.map(t=><option key={t.id} value={t.id} disabled={occupiedTables.has(t.id)&&t.id!==tableId}>
              {t.name}{t.seats?" — "+t.seats+" lugares":""}{occupiedTables.has(t.id)&&t.id!==tableId?" — ocupada":""}
            </option>)}
          </select></label>

          <label className="field"><span>Cliente</span><select value={customerId} onChange={e=>{setCustomerId(e.target.value);setDirty(true)}}>
            <option value="">Consumidor final</option>
            {customers.map(c=><option key={c.id} value={c.id}>{c.name}{c.phone?" — "+c.phone:""}</option>)}
          </select></label>
        </div>

        <label className="field"><span>Observação</span><input value={note} onChange={e=>{setNote(e.target.value);setDirty(true)}} placeholder="Ex.: mesa 4, sem açúcar..." /></label>

        <label className="field">
          <span>Adicionar produto</span>
          <input placeholder="Buscar produto..." value={search} onChange={e=>setSearch(e.target.value)} />
        </label>

        <div style={{display:"grid",gridTemplateColumns:"repeat(3,minmax(0,1fr))",gap:8}}>
          {filtered.map(p=><button
            type="button"
            key={p.id}
            onClick={()=>add(p)}
            style={{padding:11,border:"1px solid #eee",borderRadius:9,background:"#fff",textAlign:"left"}}
          >
            <b>{p.name}</b>
            <div>{money(Number(p.sale_price))}</div>
            <small>{p.is_stock_item?"Estoque atual: "+Number(p.stock_quantity).toFixed(3):"Sem controle de estoque"}</small>
          </button>)}
        </div>

        <div style={{marginTop:18}}>
          {cart.length===0?<p>Nenhum item na comanda.</p>:cart.map(item=><div
            key={item.id}
            style={{display:"grid",gridTemplateColumns:"1fr auto auto",gap:10,alignItems:"center",padding:"10px 0",borderBottom:"1px solid #eee"}}
          >
            <div><b>{item.name}</b><div className="subtitle">{money(Number(item.sale_price))} × {item.quantity}</div></div>
            <div style={{display:"flex",gap:6,alignItems:"center"}}>
              <button type="button" onClick={()=>decrease(item.id)}>-</button>
              <span>{item.quantity}</span>
              <button type="button" onClick={()=>add(item)}>+</button>
            </div>
            <div style={{textAlign:"right"}}>
              <b>{money(Number(item.sale_price)*item.quantity)}</b>
              <div><button type="button" onClick={()=>remove(item.id)} style={{border:0,background:"transparent"}}>Remover</button></div>
            </div>
          </div>)}
        </div>

        <div style={{marginTop:18,fontSize:24,fontWeight:800}}>Total: {money(total)}</div>

        <div className="grid" style={{gridTemplateColumns:"1fr 1fr",gap:10}}>
          <label className="field"><span>Pagamento no fechamento</span><select value={paymentMethod} onChange={e=>setPaymentMethod(e.target.value)}>
            {paymentMethods.map(([value,label])=><option key={value} value={value}>{label}</option>)}
          </select></label>
          <div className="field"><span>Estado</span><div style={{padding:"12px 0"}}>{dirty?"Alterações não salvas":editingId?"Comanda salva":"Ainda não aberta"}</div></div>
        </div>

        <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:10,marginTop:6}}>
          <button type="button" className="btn" disabled={saving||!cart.length} onClick={saveOrder}>
            {saving?"Processando...":editingId?"Salvar alterações":"Abrir comanda"}
          </button>
          <button type="button" className="btn" disabled={saving||!cart.length||!session} onClick={finalizeOrder}>
            {saving?"Processando...":"Finalizar e cobrar"}
          </button>
        </div>

        <button
          type="button"
          onClick={cancelOrder}
          disabled={saving||(!editingId&&!cart.length)}
          style={{marginTop:10,width:"100%",padding:12,borderRadius:9,border:"1px solid #ddd",background:"#fff",cursor:"pointer"}}
        >
          {editingId?"Cancelar comanda":"Limpar editor"}
        </button>
      </section>
    </div>
  </main>;
}
