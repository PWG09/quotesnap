"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { FormEvent, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const searchParams = useSearchParams();
  const [email,setEmail]=useState("");
  const [password,setPassword]=useState("");
  const [error,setError]=useState("");
  const [loading,setLoading]=useState(false);

  async function submit(e:FormEvent){
    e.preventDefault(); setError(""); setLoading(true);
    const supabase=createClient();
    const {error}=await supabase.auth.signInWithPassword({email:email.trim(),password});
    if(error){setError("Email or password is incorrect.");setLoading(false);return;}
    window.location.href="/dashboard";
  }

  const callbackError=searchParams.get("error");
  return <main className="auth-page"><div className="auth-card">
    <Link href="/" className="logo">QuoteSnap</Link>
    <h1>Welcome back</h1><p className="muted">Sign in to manage your quotes.</p>
    {callbackError&&<div className="error">We couldn't complete that sign-in. Please try again.</div>}
    {error&&<div className="error">{error}</div>}
    <form onSubmit={submit} className="stack">
      <label>Email<input className="input" type="email" autoComplete="email" required value={email} onChange={e=>setEmail(e.target.value)}/></label>
      <label>Password<input className="input" type="password" autoComplete="current-password" required value={password} onChange={e=>setPassword(e.target.value)}/></label>
      <button className="btn primary" disabled={loading}>{loading?"Signing in…":"Sign in"}</button>
    </form>
    <p className="muted">Don't have an account? <Link href="/signup" className="link">Create one</Link></p>
  </div></main>;
}
