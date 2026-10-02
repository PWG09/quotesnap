"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function SignupPage() {
  const [email,setEmail]=useState(""); const [password,setPassword]=useState(""); const [confirm,setConfirm]=useState("");
  const [error,setError]=useState(""); const [message,setMessage]=useState(""); const [loading,setLoading]=useState(false);

  async function submit(e:FormEvent){
    e.preventDefault(); setError(""); setMessage("");
    if(password.length<8){setError("Use at least 8 characters for your password.");return;}
    if(password!==confirm){setError("Passwords do not match.");return;}
    setLoading(true);
    const supabase=createClient();
    const origin=window.location.origin;
    const {data,error}=await supabase.auth.signUp({email:email.trim(),password,options:{emailRedirectTo:`${origin}/auth/callback`}});
    if(error){setError(error.message);setLoading(false);return;}
    if(data.session){window.location.href="/onboarding";return;}
    setMessage("Check your email to verify your account, then come back to sign in.");
    setLoading(false);
  }

  return <main className="auth-page"><div className="auth-card">
    <Link href="/" className="logo">QuoteSnap</Link>
    <h1>Create your account</h1><p className="muted">Start with a secure QuoteSnap account.</p>
    {error&&<div className="error">{error}</div>}{message&&<div className="success">{message}</div>}
    <form onSubmit={submit} className="stack">
      <label>Email<input className="input" type="email" autoComplete="email" required value={email} onChange={e=>setEmail(e.target.value)}/></label>
      <label>Password<input className="input" type="password" autoComplete="new-password" minLength={8} required value={password} onChange={e=>setPassword(e.target.value)}/></label>
      <label>Confirm password<input className="input" type="password" autoComplete="new-password" minLength={8} required value={confirm} onChange={e=>setConfirm(e.target.value)}/></label>
      <button className="btn primary" disabled={loading}>{loading?"Creating account…":"Create account"}</button>
    </form>
    <p className="muted">Already have an account? <Link href="/login" className="link">Sign in</Link></p>
  </div></main>;
}
