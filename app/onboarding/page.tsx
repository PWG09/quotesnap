"use client";

import { FormEvent,useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

function slugify(value:string){return value.toLowerCase().trim().replace(/[^a-z0-9]+/g,"-").replace(/^-+|-+$/g,"").slice(0,60);}

export default function Onboarding(){
  const router=useRouter(); const [name,setName]=useState(""); const [error,setError]=useState(""); const [loading,setLoading]=useState(false);
  async function submit(e:FormEvent){e.preventDefault();setError("");const slug=slugify(name);if(!slug){setError("Enter your business name.");return;}setLoading(true);
    const res=await fetch("/api/onboarding",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({name,slug})});
    const data=await res.json();if(!res.ok){setError(data.error||"We couldn't create your workspace.");setLoading(false);return;}router.replace("/dashboard");
  }
  return <main className="auth-page"><div className="auth-card"><div className="logo">QuoteSnap</div><h1>Set up your business</h1><p className="muted">This is the workspace where your customers, services and quotes will live.</p>{error&&<div className="error">{error}</div>}<form onSubmit={submit} className="stack"><label>Business name<input className="input" required maxLength={120} value={name} onChange={e=>setName(e.target.value)} placeholder="Acme Services"/></label><button className="btn primary" disabled={loading}>{loading?"Setting up…":"Continue to dashboard"}</button></form></div></main>;
}
