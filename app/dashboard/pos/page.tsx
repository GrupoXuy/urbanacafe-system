"use client";
import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

type Product={id:string;name:string;sale_price:number;stock_quantity:number;is_stock_item:boolean};
type CartItem=Product&{quantity:number};
type Customer={id:string;name:string;phone:string|null};
type CafeTable={id:string;name:string;seats:number|null};

const paymentMethods=[
  ["cash","Dinheiro"],
  ["debit","Débito"],
  ["credit","Crédito"],
  ["transfer","Transferência"],
  ["mercado_pago","Mercado Pago"],
  ["other","Outro"]
] as const;

export default function POS(){
  const [products,setProducts]=useState<Product[]>([]);
  const [customers,setCustomers]=useState<Customer[]>([]);
  const [tables,setTables]=useState<CafeTable[]>([]);
  const [search,setSearch]=useState("");
  const [cart,setCart]=useState<CartItem[]>([]);
  const [business,setBusiness]=useState("");
  const [session,setSession]=useState<any>(null);
  const [customerId,setCustomerId]=useState("");
  const [tableId,setTableId]=useState("");
  const [note,setNote]=useState("");
  const [paymentMethod,setPaymentMethod]=useState("cash");
  const [message,setMessage]=useState("");
  const [saving,setSaving]=useState(false);

  async function load(){
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user)return;
    const {data:m}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(!m)return;
    setBusiness(m.business_id);

    const [{data:s},{data:p},{data:cu},{data:t}]=await Promise.all([
      c.from("cash_sessions").select("*").eq("business_id",m.business_id).eq("status","open").maybeSingle(),
      c.from("products").select("id,name,sale_price,stock_quantity,is_stock_item").eq("business_id",m.business_id).eq("active",true).eq("is_sellable",true).order("name"),
      c.from("customers").select("id,name,phone").eq("business_id",m.business_id).eq("active",true).order("name"),
      c.from("cafe_tables").select("id,name,seats").eq("business_id",m.business_id).eq("active",true).order("name")
    ]);

    setSession(s);
    setProducts((p||[]) as Product[]);
    setCustomers((cu||[]) as Customer[]);
    setTables((t||[]) as CafeTable[]);
  }

  useEffect(()=>{load()},[]);

  const filtered=products.filter(p=>p.name.toLowerCase().includes(search.toLowerCase()));
  const total=useMemo(()=>cart.reduce((sum,item)=>sum+Number(item.sale_price)*item.quantity,0),[cart]);

  function add(p:Product){
    if(p.is_stock_item&&Number(p.stock_quantity)<=0){
      setMessage("Produto sem estoque disponível.");
      return;
    }
    setCart(old=>{
      const current=old.find(i=>i.id===p.id);
      const nextQuantity=(current?.quantity||0)+1;
      if(p.is_stock_item&&nextQuantity>Number(p.stock_quantity)){
        setMessage("Quantidade maior que o estoque disponível.");
        return old;
      }
      return current
        ? old.map(i=>i.id===p.id?{...i,quantity:nextQuantity}:i)
        : [...old,{...p,quantity:1}];
    });
  }

  function decrease(id:string){
    setCart(old=>old.map(i=>i.id===id?{...i,quantity:i.quantity-1}:i).filter(i=>i.quantity>0));
  }

  function remove(id:string){setCart(old=>old.filter(i=>i.id!==id));}

  async function finalize(){
    setMessage("");
    if(!business||!session){
      setMessage("Abra o caixa antes de finalizar a venda.");
      return;
    }
    if(!cart.length){
      setMessage("Adicione pelo menos um produto.");
      return;
    }

    setSaving(true);
    const c=createClient();
    const {error}=await c.rpc("create_sale_transaction",{
      p_business_id:business,
      p_cash_session_id:session.id,
      p_customer_id:customerId||null,
      p_table_id:tableId||null,
      p_notes:note.trim()||null,
      p_payment_method:paymentMethod,
      p_items:cart.map(i=>({product_id:i.id,quantity:i.quantity})),
      p_discount:0
    });

    if(error){
      setMessage(error.message);
    }else{
      setMessage("Venda finalizada com sucesso.");
      setCart([]);
      setCustomerId("");
      setTableId("");
      setNote("");
      setPaymentMethod("cash");
      await load();
    }
    setSaving(false);
  }

  return <div className="shell">
    <aside className="sidebar">
      <div className="brand">URBANA <span>CAFÉ</span></div>
      <nav className="nav">
        <Link href="/dashboard">Dashboard</Link>
        <Link className="active" href="/dashboard/pos">Vendas / POS</Link>
        <Link href="/dashboard/caixa">Caixa</Link>
        <Link href="/dashboard/estoque">Estoque</Link>
        <Link href="/dashboard/produtos">Produtos</Link>
        <Link href="/dashboard/compras">Compras</Link>
        <Link href="/dashboard/despesas">Despesas</Link>
        <Link href="/dashboard/clientes">Clientes</Link>
        <Link href="/dashboard/mesas">Mesas</Link>
        <Link href="/dashboard/reservas">Reservas</Link>
        <Link href="/dashboard/relatorios">Relatórios</Link>
        <Link href="/dashboard/funcionarios">Funcionários</Link>
      </nav>
    </aside>

    <main className="main">
      <div className="topbar">
        <div><h1 className="title">Vendas / POS</h1><div className="subtitle">Atendimento, venda e pagamento</div></div>
        <div className={session?"positive":"negative"}>{session?"Caixa aberto":"Caixa fechado"}</div>
      </div>

      {!session&&<div className="notice">O caixa está fechado. Abra uma sessão em <Link href="/dashboard/caixa">Caixa</Link> para finalizar vendas.</div>}

      <div className="grid" style={{gridTemplateColumns:"minmax(0,2fr) minmax(320px,1fr)"}}>
        <div className="card">
          <input placeholder="Buscar produto..." value={search} onChange={e=>setSearch(e.target.value)}
            style={{width:"100%",padding:12,border:"1px solid #ddd",borderRadius:9}} />
          <div style={{display:"grid",gridTemplateColumns:"repeat(3,minmax(0,1fr))",gap:10,marginTop:14}}>
            {filtered.map(p=><button key={p.id} onClick={()=>add(p)} disabled={p.is_stock_item&&Number(p.stock_quantity)<=0}
              style={{padding:14,border:"1px solid #eee",borderRadius:10,background:"#fff",textAlign:"left",cursor:p.is_stock_item&&Number(p.stock_quantity)<=0?"not-allowed":"pointer"}}>
              <b>{p.name}</b><div>UYU {Number(p.sale_price).toFixed(2)}</div>
              <small>{p.is_stock_item?(Number(p.stock_quantity)>0?("Estoque: "+p.stock_quantity):"Sem estoque"):"Item sem controle de estoque"}</small>
            </button>)}
          </div>
          {filtered.length===0&&<p className="subtitle" style={{marginTop:16}}>Nenhum produto encontrado. Cadastre produtos em <Link href="/dashboard/produtos">Produtos</Link>.</p>}
        </div>

        <div className="card">
          <div className="label">Comanda atual</div>
          <div className="grid" style={{gridTemplateColumns:"1fr 1fr",gap:10,marginTop:12}}>
            <label className="field"><span>Cliente</span><select value={customerId} onChange={e=>setCustomerId(e.target.value)}>
              <option value="">Consumidor final</option>{customers.map(c=><option key={c.id} value={c.id}>{c.name}{c.phone?" — "+c.phone:""}</option>)}
            </select></label>
            <label className="field"><span>Mesa</span><select value={tableId} onChange={e=>setTableId(e.target.value)}>
              <option value="">Balcão / sem mesa</option>{tables.map(t=><option key={t.id} value={t.id}>{t.name}{t.seats?" — "+t.seats+" lugares":""}</option>)}
            </select></label>
          </div>

          <div className="grid" style={{gridTemplateColumns:"1fr 1fr",gap:10}}>
            <label className="field"><span>Forma de pagamento</span><select value={paymentMethod} onChange={e=>setPaymentMethod(e.target.value)}>
              {paymentMethods.map(([value,label])=><option key={value} value={value}>{label}</option>)}
            </select></label>
            <div className="field"><span>Sessão de caixa</span><div style={{padding:"12px 0"}}>{session?"Aberta":"Fechada"}</div></div>
          </div>

          <label className="field"><span>Observação</span><input value={note} onChange={e=>setNote(e.target.value)} placeholder="Ex.: sem açúcar, retirar guardanapo..." /></label>

          <div style={{marginTop:12}}>
            {cart.length===0?<p>Nenhum item.</p>:cart.map(item=><div key={item.id}
              style={{display:"grid",gridTemplateColumns:"1fr auto auto",gap:10,alignItems:"center",padding:"10px 0",borderBottom:"1px solid #eee"}}>
              <div><b>{item.name}</b><div className="subtitle">UYU {Number(item.sale_price).toFixed(2)} × {item.quantity}</div></div>
              <div style={{display:"flex",gap:6,alignItems:"center"}}><button onClick={()=>decrease(item.id)}>-</button><span>{item.quantity}</span><button onClick={()=>add(item)}>+</button></div>
              <div style={{textAlign:"right"}}><b>UYU {(Number(item.sale_price)*item.quantity).toFixed(2)}</b><div><button onClick={()=>remove(item.id)} style={{border:0,background:"transparent",cursor:"pointer"}}>Remover</button></div></div>
            </div>)}
          </div>

          <div style={{marginTop:18,fontSize:24,fontWeight:800}}>Total: UYU {total.toFixed(2)}</div>
          <button className="btn" style={{marginTop:14}} disabled={!cart.length||saving||!session} onClick={finalize}>
            {saving?"Processando...":"Finalizar venda"}
          </button>
          {message&&<div className="notice">{message}</div>}
        </div>
      </div>
    </main>
  </div>
}
