import{createContext,useContext,useEffect,useState,type ReactNode}from'react';
const API='/api';
type User={id:string;full_name:string;email:string;role:string;rango?:string;telefono?:string;cargo?:string;permisos:Record<string,boolean>};
type Auth={user:User|null;token:string|null;login:(e:string,p:string)=>Promise<void>;logout:()=>void;refresh:()=>Promise<void>};
const C=createContext<Auth>(null!);
export async function api(path:string,options:RequestInit={}){const token=localStorage.getItem('gp_token');const r=await fetch(API+path,{...options,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{}) ,...options.headers}});if(r.status===204)return null;const body=await r.json();if(!r.ok)throw new Error(body.message||'No fue posible completar la operación');return body;}
export function AuthProvider({children}:{children:ReactNode}){const[token,setToken]=useState(localStorage.getItem('gp_token'));const[user,setUser]=useState<User|null>(null);const refresh=async()=>{if(!token)return;try{setUser(await api('/auth/me'))}catch{logout()}};useEffect(()=>{refresh()},[token]);const login=async(email:string,password:string)=>{const d=await api('/auth/login',{method:'POST',body:JSON.stringify({email,password})});localStorage.setItem('gp_token',d.token);setToken(d.token);setUser(d.user)};const logout=()=>{localStorage.removeItem('gp_token');setToken(null);setUser(null)};return <C.Provider value={{user,token,login,logout,refresh}}>{children}</C.Provider>}
export const useAuth=()=>useContext(C);

