import { Navigate,Route,Routes } from 'react-router-dom';
import { useAuth } from './state';
import { Layout } from './components';
import{lazy,Suspense}from'react';
const Login=lazy(()=>import('./pages/Login')),Dashboard=lazy(()=>import('./pages/Dashboard')),CrudPage=lazy(()=>import('./pages/CrudPage')),Rondas=lazy(()=>import('./pages/Rondas')),Turnos=lazy(()=>import('./pages/Turnos')),Relevos=lazy(()=>import('./pages/Relevos')),Users=lazy(()=>import('./pages/Users')),Profile=lazy(()=>import('./pages/Profile')),Config=lazy(()=>import('./pages/Config')),PublicPage=lazy(()=>import('./pages/PublicPage')),RRHH=lazy(()=>import('./pages/RRHH')),Empresas=lazy(()=>import('./pages/Empresas')),MiEmpresa=lazy(()=>import('./pages/MiEmpresa'));

export default function App(){
  const {token,user}=useAuth();
  if(!token)return <Suspense fallback={<Loading/>}><Routes><Route path="/" element={<PublicPage/>}/><Route path="/empresa" element={<PublicPage/>}/><Route path="/login" element={<Login/>}/><Route path="*" element={<Navigate to="/"/>}/></Routes></Suspense>;
  if(!user)return <div className="grid min-h-screen place-items-center bg-slate-50 text-sm font-semibold text-slate-500">Cargando sesión…</div>;
  if(user?.must_change_password)return <Layout><Suspense fallback={<Loading/>}><Routes><Route path="/perfil" element={<Profile/>}/><Route path="*" element={<Navigate to="/perfil"/>}/></Routes></Suspense></Layout>;
  const allowed=(module:string)=>user?.role==='superadmin'||(user?.empresa_modulos?.[module]!==false&&(user?.role==='admin'||user?.permisos?.[module]===true));
  return <Layout><Suspense fallback={<Loading/>}><Routes>
    <Route path="/" element={<Navigate to={user.role==='superadmin'?'/empresas':'/dashboard'}/>}/><Route path="/login" element={<Navigate to={user.role==='superadmin'?'/empresas':'/dashboard'}/>}/><Route path="/dashboard" element={user.role==='superadmin'?<Navigate to="/empresas"/>:<Dashboard/>}/>
    {['guardias','recintos','entradas','reportes','alertas'].map(module=><Route key={module} path={'/'+module} element={allowed(module)?<CrudPage moduleKey={module}/>:<Navigate to="/dashboard"/>}/>)}
    <Route path="/turnos" element={allowed('turnos')?<Turnos/>:<Navigate to="/dashboard"/>}/><Route path="/relevos" element={allowed('relevos')?<Relevos/>:<Navigate to="/dashboard"/>}/><Route path="/rondas" element={allowed('rondas')?<Rondas/>:<Navigate to="/dashboard"/>}/><Route path="/rrhh" element={allowed('rrhh')?<RRHH/>:<Navigate to="/dashboard"/>}/><Route path="/usuarios" element={['admin','superadmin'].includes(user?.role||'')?<Users/>:<Navigate to="/dashboard"/>}/><Route path="/empresas" element={user?.role==='superadmin'?<Empresas/>:<Navigate to="/dashboard"/>}/><Route path="/mi-empresa" element={user?.role==='admin'?<MiEmpresa/>:<Navigate to="/dashboard"/>}/><Route path="/perfil" element={<Profile/>}/><Route path="/configuracion" element={user.role==='superadmin'?<Config/>:<Navigate to="/dashboard"/>}/><Route path="/empresa" element={<PublicPage/>}/><Route path="*" element={<Navigate to="/dashboard"/>}/>
  </Routes></Suspense></Layout>;
}
function Loading(){return <div className="grid min-h-48 place-items-center text-sm font-semibold text-slate-500">Cargando módulo…</div>}
