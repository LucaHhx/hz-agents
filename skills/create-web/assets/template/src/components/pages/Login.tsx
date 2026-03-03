import { useState } from 'react';
import { useAuth } from '../../context/AppContext';
import Icon from '../ui/Icon';

const VALID_USERNAME = 'admin';
const VALID_PASSWORD = '123456';

export default function Login() {
  const { login } = useAuth();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!username.trim() || !password.trim()) {
      setError('请输入用户名和密码');
      return;
    }
    if (username === VALID_USERNAME && password === VALID_PASSWORD) {
      login(username);
    } else {
      setError('用户名或密码错误');
    }
  };

  return (
    <div className="login-page">
      <form className="login-card" onSubmit={handleSubmit}>
        <div className="login-logo">
          <div className="logo-icon">D</div>
        </div>
        <h1 className="login-title">Dashboard</h1>
        <p className="login-subtitle">登录以继续</p>
        <div className="login-divider" />
        <div className="form-group" style={{ marginBottom: 16 }}>
          <label className="form-label">用户名</label>
          <div className="login-input-wrap">
            <Icon name="user" size={16} />
            <input
              className={`form-input ${error ? 'error' : ''}`}
              type="text"
              value={username}
              onChange={e => { setUsername(e.target.value); setError(''); }}
              placeholder="请输入用户名"
              autoComplete="username"
            />
          </div>
        </div>
        <div className="form-group" style={{ marginBottom: 8 }}>
          <label className="form-label">密码</label>
          <div className="login-input-wrap">
            <Icon name="lock" size={16} />
            <input
              className={`form-input ${error ? 'error' : ''}`}
              type="password"
              value={password}
              onChange={e => { setPassword(e.target.value); setError(''); }}
              placeholder="请输入密码"
              autoComplete="current-password"
            />
          </div>
        </div>
        {error && <span className="form-error" style={{ marginBottom: 8, display: 'block' }}>{error}</span>}
        <button type="submit" className="btn-primary" style={{ marginTop: 16 }}>
          登 录
        </button>
      </form>
    </div>
  );
}
