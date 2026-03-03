import { useState } from 'react';
import { useToast, useModal } from '../../context/AppContext';
import Card from '../ui/Card';
import Button from '../ui/Button';
import Avatar from '../ui/Avatar';
import TabSwitcher from '../ui/TabSwitcher';
import ProgressBar from '../ui/ProgressBar';
import SearchBox from '../ui/SearchBox';
import EmptyState from '../ui/EmptyState';
import FormInput from '../form/FormInput';
import FormSelect from '../form/FormSelect';
import AmountInput from '../form/AmountInput';
import DatePicker from '../form/DatePicker';
import ToggleSwitch from '../form/ToggleSwitch';

export default function DemoPage() {
  const toast = useToast();
  const modal = useModal();
  const [tab, setTab] = useState(0);
  const [text, setText] = useState('');
  const [search, setSearch] = useState('');
  const [select, setSelect] = useState('');
  const [amount, setAmount] = useState('');
  const [date, setDate] = useState('');
  const [toggle, setToggle] = useState(false);

  return (
    <>
      {/* Buttons */}
      <Card title="按钮 Button">
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12 }}>
          <Button variant="primary" onClick={() => toast('操作成功', 'success')}>主按钮</Button>
          <Button variant="secondary" onClick={() => toast('提示信息', 'info')}>次按钮</Button>
          <Button variant="danger" onClick={() => toast('危险操作', 'error')}>危险按钮</Button>
          <Button variant="ghost" onClick={() => toast('警告信息', 'warning')}>幽灵按钮</Button>
          <Button disabled>禁用</Button>
        </div>
      </Card>

      {/* Avatars */}
      <Card title="头像 Avatar">
        <div style={{ display: 'flex', gap: 16, alignItems: 'center' }}>
          <Avatar icon="user" color="#3b82f6" size={48} />
          <Avatar initials="A" color="#22c55e" size={48} />
          <Avatar initials="B" color="#f97316" size={40} />
          <Avatar icon="wallet" color="#a855f7" size={36} />
        </div>
      </Card>

      {/* Tabs */}
      <Card title="标签切换 TabSwitcher">
        <TabSwitcher tabs={['全部', '进行中', '已完成']} activeIndex={tab} onChange={setTab} />
        <p className="text-muted" style={{ marginTop: 12, fontSize: 13 }}>
          当前选中: 第 {tab + 1} 项
        </p>
      </Card>

      {/* Forms */}
      <Card title="表单 Form">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <FormInput label="文本输入" value={text} onChange={setText} placeholder="请输入..." />
          <FormInput label="错误状态" value="" onChange={() => {}} error="这是错误提示" placeholder="示例" />
          <FormSelect
            label="下拉选择"
            value={select}
            onChange={setSelect}
            placeholder="请选择..."
            options={[
              { value: 'a', label: '选项 A' },
              { value: 'b', label: '选项 B' },
              { value: 'c', label: '选项 C' },
            ]}
          />
          <DatePicker label="日期选择" value={date} onChange={setDate} />
          <ToggleSwitch label="开关控件" checked={toggle} onChange={setToggle} />
        </div>
      </Card>

      {/* Amount Input */}
      <Card title="金额输入 AmountInput">
        <AmountInput value={amount} onChange={setAmount} />
      </Card>

      {/* Search */}
      <Card title="搜索框 SearchBox">
        <SearchBox value={search} onChange={setSearch} placeholder="搜索内容..." />
      </Card>

      {/* Progress */}
      <Card title="进度条 ProgressBar">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <ProgressBar label="正常进度" current={650} total={1000} />
          <ProgressBar label="超额状态" current={1200} total={1000} color="#3b82f6" />
          <ProgressBar label="低进度" current={150} total={1000} color="#f97316" />
        </div>
      </Card>

      {/* Modal */}
      <Card title="弹窗 Modal">
        <Button variant="secondary" onClick={() => modal.open(
          <div>
            <div className="modal-row"><span className="ml">项目</span><span className="mv">示例数据</span></div>
            <div className="modal-row"><span className="ml">状态</span><span className="mv">进行中</span></div>
            <div className="modal-row"><span className="ml">金额</span><span className="mv">¥1,234.56</span></div>
          </div>
        )}>打开弹窗</Button>
      </Card>

      {/* Empty State */}
      <Card title="空状态 EmptyState">
        <EmptyState icon="search" message="暂无搜索结果" />
      </Card>
    </>
  );
}
