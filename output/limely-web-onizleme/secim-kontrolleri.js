'use strict';

// Shared presentation controls. Native values retain the existing form/change flow.
window.LimelyFields = (() => {
  let icon;
  let opened = null;
  const esc = value => String(value).replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const dateAt = (year, month, day) => new Date(Date.UTC(year, month, day));
  const parseDate = value => /^\d{4}-\d{2}-\d{2}$/.test(value) ? dateAt(...value.split('-').map((part,index)=>Number(part)-(index===1?1:0))) : null;
  const iso = date => date.toISOString().slice(0,10);
  const formatDate = value => {
    const date=parseDate(value);
    return date ? date.toLocaleDateString('tr-TR',{day:'numeric',month:'long',year:'numeric',timeZone:'UTC'}) : 'Tarih seç';
  };

  function select({label,id,value,options,attributes=''}) {
    const selected=options.find(([key])=>String(key)===String(value)) ?? options[0];
    return `<div class="custom-select"><select id="${id}" hidden tabindex="-1" aria-hidden="true" ${attributes}>${options.map(([key,text])=>`<option value="${esc(key)}"${String(key)===String(value)?' selected':''}>${esc(text)}</option>`).join('')}</select><button id="${id}-trigger" type="button" class="select-trigger" role="combobox" aria-label="${esc(label)}" aria-haspopup="listbox" aria-expanded="false" aria-controls="${id}-options" data-select-trigger="${id}"><span class="select-value">${esc(selected[1])}</span>${icon('chevron')}</button><div id="${id}-options" class="floating-menu select-menu" role="listbox" aria-label="${esc(label)} seçenekleri" popover="manual" hidden>${options.map(([key,text],index)=>`<div id="${id}-option-${index}" class="select-option" role="option" aria-selected="${String(key)===String(value)}" data-option-index="${index}" data-value="${esc(key)}"><span>${esc(text)}</span><span class="option-check" aria-hidden="true">${icon('check')}</span></div>`).join('')}</div></div>`;
  }

  function date({label,id,value,required=false}) {
    return `<div class="input-wrap date-control"><input id="${id}" type="date" value="${esc(value)}" ${required?'required':''} hidden tabindex="-1" aria-hidden="true"><button id="${id}-trigger" type="button" class="date-trigger" aria-label="${esc(label)}" aria-haspopup="dialog" aria-expanded="false" aria-controls="${id}-calendar" data-date-trigger="${id}">${icon('calendar')}<span class="date-value">${formatDate(value)}</span>${icon('chevron')}</button><div id="${id}-calendar" class="floating-menu calendar-menu" role="dialog" aria-label="${esc(label)} seç" popover="manual" hidden></div></div>`;
  }

  function closeAll(focus=false) {
    if(!opened)return;
    const current=opened;opened=null;
    if(current.menu.isConnected&&current.menu.matches(':popover-open'))current.menu.hidePopover();
    current.menu.classList.remove('is-open');current.menu.hidden=true;
    current.trigger.setAttribute('aria-expanded','false');current.trigger.removeAttribute('aria-activedescendant');
    if(focus&&current.trigger.isConnected)current.trigger.focus({preventScroll:true});
  }

  function position() {
    if(!opened||!opened.trigger.isConnected){closeAll();return;}
    const {menu,trigger,kind}=opened;
    const anchor=trigger.closest('.filter-control,.input-wrap') ?? trigger;
    const box=anchor.getBoundingClientRect(), gap=8, margin=12;
    if(box.bottom<0||box.top>innerHeight){closeAll();return;}
    const width=Math.min(kind==='date'?330:Math.max(box.width,240),innerWidth-margin*2);
    menu.style.width=`${width}px`;menu.style.maxHeight=`${innerHeight-margin*2}px`;
    const idealHeight=Math.min(menu.scrollHeight,kind==='date'?420:320);
    const below=innerHeight-box.bottom-margin-gap, above=box.top-margin-gap;
    const upwards=below<idealHeight&&above>below;
    const space=Math.max(72,upwards?above:below);
    menu.style.maxHeight=`${Math.min(space,kind==='date'?420:320)}px`;
    const height=menu.getBoundingClientRect().height;
    const left=Math.min(Math.max(margin,box.left),innerWidth-width-margin);
    const top=upwards?box.top-height-gap:box.bottom+gap;
    menu.style.left=`${left}px`;menu.style.top=`${Math.max(margin,Math.min(top,innerHeight-height-margin))}px`;
    menu.dataset.placement=upwards?'above':'below';
  }

  function show(current) {
    closeAll();
    document.querySelectorAll('details[open]').forEach(detail=>{detail.open=false;});
    opened=current;current.menu.hidden=false;
    current.trigger.setAttribute('aria-expanded','true');
    if(typeof current.menu.showPopover==='function')current.menu.showPopover();
    else current.menu.classList.add('is-open');
    position();
  }

  function activate(index) {
    if(!opened||opened.kind!=='select')return;
    const {menu,trigger,input}=opened;
    index=Math.max(0,Math.min(index,input.options.length-1));opened.active=index;
    menu.querySelectorAll('[role="option"]').forEach((option,i)=>option.classList.toggle('is-active',i===index));
    const option=menu.querySelector(`[data-option-index="${index}"]`);
    trigger.setAttribute('aria-activedescendant',option.id);
    if(option.offsetTop<menu.scrollTop)menu.scrollTop=option.offsetTop;
    else if(option.offsetTop+option.offsetHeight>menu.scrollTop+menu.clientHeight)menu.scrollTop=option.offsetTop+option.offsetHeight-menu.clientHeight;
  }

  function openSelect(trigger) {
    const input=document.getElementById(trigger.dataset.selectTrigger);
    show({kind:'select',trigger,input,menu:document.getElementById(`${input.id}-options`),active:input.selectedIndex,search:'',lastSearch:0});
    activate(input.selectedIndex);
  }

  function choose(index) {
    const {input,trigger}=opened;
    if(!input.options[index]||input.options[index].disabled)return;
    input.selectedIndex=index;
    trigger.querySelector('.select-value').textContent=input.options[index].textContent;
    opened.menu.querySelectorAll('[role="option"]').forEach((option,i)=>option.setAttribute('aria-selected',String(i===index)));
    closeAll(true);input.dispatchEvent(new Event('change',{bubbles:true}));
  }

  function monthShift(date,amount) {
    const first=dateAt(date.getUTCFullYear(),date.getUTCMonth()+amount,1);
    const last=dateAt(first.getUTCFullYear(),first.getUTCMonth()+1,0).getUTCDate();
    return dateAt(first.getUTCFullYear(),first.getUTCMonth(),Math.min(date.getUTCDate(),last));
  }

  function calendar(focus=false) {
    const current=opened;if(!current||current.kind!=='date')return;
    const date=parseDate(current.activeDate),year=date.getUTCFullYear(),month=date.getUTCMonth();
    const first=dateAt(year,month,1),offset=(first.getUTCDay()+6)%7;
    const now=new Date(),today=iso(dateAt(now.getFullYear(),now.getMonth(),now.getDate()));
    const title=first.toLocaleDateString('tr-TR',{month:'long',year:'numeric',timeZone:'UTC'});
    const cells=Array.from({length:42},(_,index)=>{
      const item=dateAt(year,month,index-offset+1),value=iso(item);
      const cls=['calendar-day',item.getUTCMonth()!==month?'is-adjacent':'',value===current.input.value?'is-selected':'',value===today?'is-today':''].filter(Boolean).join(' ');
      return `<button type="button" role="gridcell" class="${cls}" data-calendar-date="${value}" tabindex="${value===current.activeDate?'0':'-1'}" aria-label="${formatDate(value)}" aria-selected="${value===current.input.value}"${value===today?' aria-current="date"':''}>${item.getUTCDate()}</button>`;
    });
    current.menu.innerHTML=`<header class="calendar-header"><button type="button" class="calendar-arrow" data-calendar-action="previous" aria-label="Önceki ay">${icon('left')}</button><h2 id="${current.input.id}-month">${title}</h2><button type="button" class="calendar-arrow" data-calendar-action="next" aria-label="Sonraki ay">${icon('right')}</button></header><div class="calendar-grid" role="grid" aria-labelledby="${current.input.id}-month"><div class="calendar-weekdays" role="row">${['Pzt','Sal','Çar','Per','Cum','Cmt','Paz'].map(day=>`<span role="columnheader">${day}</span>`).join('')}</div>${Array.from({length:6},(_,row)=>`<div class="calendar-row" role="row">${cells.slice(row*7,row*7+7).join('')}</div>`).join('')}</div><footer class="calendar-footer"><button type="button" class="calendar-today" data-calendar-action="today">Bugün</button><span>${current.input.value?formatDate(current.input.value):'Tarih seç'}</span><button type="button" class="calendar-done" data-calendar-action="close">Kapat</button></footer>`;
    position();
    if(focus)current.menu.querySelector(`[data-calendar-date="${current.activeDate}"]`)?.focus({preventScroll:true});
  }

  function openDate(trigger) {
    const input=document.getElementById(trigger.dataset.dateTrigger);
    const now=new Date();
    const activeDate=input.value||iso(dateAt(now.getFullYear(),now.getMonth(),now.getDate()));
    const menu=document.getElementById(`${input.id}-calendar`);
    // Populate before measuring; the layer moves to the browser's top layer when shown.
    closeAll();opened={kind:'date',trigger,input,menu,activeDate};calendar();
    const current=opened;opened=null;show(current);calendar(true);
  }

  function chooseDate(value) {
    const {input,trigger}=opened;
    input.value=value;trigger.querySelector('.date-value').textContent=formatDate(value);
    closeAll(true);input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));
  }

  document.addEventListener('pointerdown',event=>{
    if(opened&&!opened.menu.contains(event.target)&&!opened.trigger.contains(event.target))closeAll();
  });
  document.addEventListener('focusin',event=>{
    if(opened&&!opened.menu.contains(event.target)&&!opened.trigger.contains(event.target))closeAll();
  });
  document.addEventListener('pointermove',event=>{
    const option=event.target.closest('[data-option-index]');
    if(option&&opened?.kind==='select'&&opened.menu.contains(option))activate(Number(option.dataset.optionIndex));
  });
  document.addEventListener('click',event=>{
    const selectTrigger=event.target.closest('[data-select-trigger]');
    if(selectTrigger){if(opened?.trigger===selectTrigger)closeAll(true);else openSelect(selectTrigger);return;}
    const option=event.target.closest('[data-option-index]');
    if(option&&opened?.kind==='select'&&opened.menu.contains(option)){choose(Number(option.dataset.optionIndex));return;}
    const dateTrigger=event.target.closest('[data-date-trigger]');
    if(dateTrigger){if(opened?.trigger===dateTrigger)closeAll(true);else openDate(dateTrigger);return;}
    if(opened?.kind!=='date'||!opened.menu.contains(event.target))return;
    const day=event.target.closest('[data-calendar-date]');
    if(day){chooseDate(day.dataset.calendarDate);return;}
    const action=event.target.closest('[data-calendar-action]')?.dataset.calendarAction;
    if(action==='close')closeAll(true);
    else if(action==='today'){const now=new Date();chooseDate(iso(dateAt(now.getFullYear(),now.getMonth(),now.getDate())));}
    else if(action==='previous'||action==='next'){opened.activeDate=iso(monthShift(parseDate(opened.activeDate),action==='next'?1:-1));calendar(true);}
  });
  document.addEventListener('keydown',event=>{
    const trigger=event.target.closest('[data-select-trigger]');
    if(trigger){
      const key=event.key,printable=key.length===1&&!event.ctrlKey&&!event.metaKey&&!event.altKey&&key!==' ';
      if(['ArrowDown','ArrowUp','Home','End','Enter',' '].includes(key)||printable){
        event.preventDefault();
        if(!opened||opened.trigger!==trigger){
          openSelect(trigger);
          if(key==='ArrowUp'||key==='End')activate(opened.input.options.length-1);
          if(key==='Home')activate(0);
          if(!printable)return;
        }
        else if(key==='Enter'||key===' '){choose(opened.active);return;}
        if(key==='ArrowDown')activate(opened.active+1);
        if(key==='ArrowUp')activate(opened.active-1);
        if(key==='Home')activate(0);
        if(key==='End')activate(opened.input.options.length-1);
        if(printable){
          const now=Date.now();opened.search=now-opened.lastSearch>700?key:opened.search+key;opened.lastSearch=now;
          const query=opened.search.toLocaleLowerCase('tr-TR');
          const index=[...opened.input.options].findIndex(option=>option.textContent.toLocaleLowerCase('tr-TR').startsWith(query));
          if(index>=0)activate(index);
        }
        return;
      }
      if(key==='Tab'){closeAll();return;}
    }
    if(event.key==='Escape'&&opened){event.preventDefault();event.stopImmediatePropagation();closeAll(true);return;}
    if(opened?.kind!=='date'||!opened.menu.contains(event.target))return;
    const day=event.target.closest('[data-calendar-date]');if(!day)return;
    const current=parseDate(day.dataset.calendarDate),key=event.key;
    let next;
    if(key==='ArrowLeft'||key==='ArrowRight'||key==='ArrowUp'||key==='ArrowDown'){
      next=dateAt(current.getUTCFullYear(),current.getUTCMonth(),current.getUTCDate()+({ArrowLeft:-1,ArrowRight:1,ArrowUp:-7,ArrowDown:7}[key]));
    }
    if(key==='PageUp'||key==='PageDown')next=monthShift(current,key==='PageUp'?-1:1);
    if(key==='Home'||key==='End'){const offset=(current.getUTCDay()+6)%7;next=dateAt(current.getUTCFullYear(),current.getUTCMonth(),current.getUTCDate()+(key==='Home'?-offset:6-offset));}
    if(next){event.preventDefault();opened.activeDate=iso(next);calendar(true);}
  });
  document.addEventListener('scroll',event=>{if(opened&&!opened.menu.contains(event.target))position();},true);
  document.addEventListener('toggle',event=>{if(event.target instanceof HTMLDetailsElement&&event.target.open)closeAll();},true);
  window.addEventListener('resize',()=>closeAll());window.addEventListener('hashchange',()=>closeAll());
  return {configure(renderer){icon=renderer;},select,date,closeAll};
})();
