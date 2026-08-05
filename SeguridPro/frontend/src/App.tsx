import { Navigate,Route,Routes } from 'react-router-dom';
import { useAuth } from './state';
import { Layout } from './components';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import CrudPage from './pages/CrudPage';
import Rondas from './pages/Rondas';
import Turnos from './pages/Turnos';
import Relevos from './pages/Relevos';
import Users from './pages/Users';
import Profile from './pages/Profile';
import Config from './pages/Config';
import PublicPage from './pages/PublicPage';

export default function App(){
  const {token,user}=useAuth();
  if(!token)return <Routes><Route path="/" element={<PublicPage/>}/><Route path="/empresa" element={<PublicPage/>}/><Route path="/login" element={<Login/>}/><Route path="*" element={<Navigate to="/"/>}/></Routes>;
  if(!user)return <div className="grid min-h-screen place-items-center bg-slate-50 text-sm font-semibold text-slate-500">Cargando sesión…</div>;
  if(user?.must_change_password)return <Layout><Routes><Route path="/perfil" element={<Profile/>}/><Route path="*" element={<Navigate to="/perfil"/>}/></Routes></Layout>;
  const allowed=(module:string)=>user?.role==='admin'||user?.permisos?.[module]===true;
  return <Layout><Routes>
    <Route path="/" element={<Navigate to="/dashboard"/>}/><Route path="/login" element={<Navigate to="/dashboard"/>}/><Route path="/dashboard" element={<Dashboard/>}/>
    {['guardias','recintos','entradas','reportes','alertas'].map(module=><Route key={module} path={'/'+module} element={allowed(module)?<CrudPage moduleKey={module}/>:<Navigate to="/dashboard"/>}/>)}
    <Route path="/turnos" element={allowed('turnos')?<Turnos/>:<Navigate to="/dashboard"/>}/><Route path="/relevos" element={allowed('relevos')?<Relevos/>:<Navigate to="/dashboard"/>}/><Route path="/rondas" element={allowed('rondas')?<Rondas/>:<Navigate to="/dashboard"/>}/><Route path="/usuarios" element={user?.role==='admin'?<Users/>:<Navigate to="/dashboard"/>}/><Route path="/perfil" element={<Profile/>}/><Route path="/configuracion" element={allowed('configuracion')?<Config/>:<Navigate to="/dashboard"/>}/><Route path="/empresa" element={<PublicPage/>}/><Route path="*" element={<Navigate to="/dashboard"/>}/>
  </Routes></Layout>;
}
