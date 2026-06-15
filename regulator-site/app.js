window.addEventListener('scroll',()=>{const h=document.documentElement;document.getElementById('scrollProgress').style.width=(h.scrollTop/(h.scrollHeight-h.clientHeight))*100+'%'});
let lastScroll=0;const nav=document.getElementById('navbar');
window.addEventListener('scroll',()=>{const c=window.pageYOffset;if(c>lastScroll&&c>80)nav.classList.add('hidden');else nav.classList.remove('hidden');lastScroll=c});
const obs=new IntersectionObserver(e=>{e.forEach(x=>{if(x.isIntersecting){x.target.classList.add('visible');obs.unobserve(x.target)}})},{threshold:.15,rootMargin:'0px 0px -40px 0px'});
document.querySelectorAll('.reveal').forEach(el=>obs.observe(el));
const cObs=new IntersectionObserver(e=>{e.forEach(x=>{if(x.isIntersecting){const el=x.target,t=parseInt(el.dataset.counter);let c=0;const s=Math.ceil(t/40);const i=setInterval(()=>{c+=s;if(c>=t){c=t;clearInterval(i)}el.textContent=c},30);cObs.unobserve(el)}})},{threshold:.5});
document.querySelectorAll('[data-counter]').forEach(el=>cObs.observe(el));
const gi=document.querySelectorAll('.gallery-item');let ci=0;
gi.forEach((it,i)=>it.addEventListener('click',()=>{ci=i;openLightbox()}));
function openLightbox(){const it=gi[ci],img=it.querySelector('img');document.getElementById('lightboxImg').src=img.src;document.getElementById('lightboxCaption').textContent=it.dataset.caption||'';document.getElementById('lightbox').classList.add('active');document.body.style.overflow='hidden'}
function closeLightbox(){document.getElementById('lightbox').classList.remove('active');document.body.style.overflow=''}
function navigateLightbox(d){ci=(ci+d+gi.length)%gi.length;openLightbox()}
document.addEventListener('keydown',e=>{if(!document.getElementById('lightbox').classList.contains('active'))return;if(e.key==='Escape')closeLightbox();if(e.key==='ArrowLeft')navigateLightbox(-1);if(e.key==='ArrowRight')navigateLightbox(1)});
document.getElementById('lightbox').addEventListener('click',e=>{if(e.target===e.currentTarget)closeLightbox()});
const RATES={dump:{day:100,weekend:180,month:0},flatbed:{day:225,week:0,month:0}};
function calcTotal(){
const trailer=document.getElementById('bookTrailer').value;
const start=new Date(document.getElementById('bookStart').value);
const end=new Date(document.getElementById('bookEnd').value);
const r=RATES[trailer];
document.getElementById('sumTrailer').textContent=trailer==='dump'?'PJ D7 Dump':'24\' Flatbed + Winch';
const del=document.getElementById('bookDelivery').value;
document.getElementById('sumDelivery').textContent=del==='pickup'?'Pickup (free)':'Delivery (quote)';
if(isNaN(start)||isNaN(end)||end<=start){
document.getElementById('sumStart').textContent='Select dates';
document.getElementById('sumEnd').textContent='Select dates';
document.getElementById('sumDays').textContent='—';
document.getElementById('sumRate').textContent=r.day+'/day';
document.getElementById('sumTotal').textContent='$0';
document.getElementById('sumSavings').style.display='none';
return;
}
const days=Math.ceil((end-start)/(1000*60*60*24));
document.getElementById('sumStart').textContent=start.toLocaleDateString('en-US',{month:'short',day:'numeric'});
document.getElementById('sumEnd').textContent=end.toLocaleDateString('en-US',{month:'short',day:'numeric'});
document.getElementById('sumDays').textContent=days+(days===1?' day':' days');
let total=0;
let d=new Date(start);
while(d<end){
const dow=d.getDay(); 
if(trailer==='dump'&&dow===6){ 
const next=new Date(d);next.setDate(next.getDate()+1);
if(next<end&&(next.getDay()===0)){
total+=r.weekend; 
d.setDate(d.getDate()+2);continue;
}
}
total+=r.day;
d.setDate(d.getDate()+1);
}
document.getElementById('sumRate').textContent=trailer==='dump'?('$100/day, $180 weekend'):'$225/day';
document.getElementById('sumTotal').textContent='$'+total.toLocaleString();
const fullDaily=days*r.day;
if(total<fullDaily){const el=document.getElementById('sumSavings');el.style.display='block';el.textContent='🎉 Weekend rate applied — you save $'+(fullDaily-total)+'!'}
else{document.getElementById('sumSavings').style.display='none'}
}
document.getElementById('bookStart').min=new Date().toISOString().split('T')[0];
document.getElementById('bookEnd').min=new Date().toISOString().split('T')[0];
function submitBooking(){
const n=document.getElementById('bookName').value;
const p=document.getElementById('bookPhone').value;
if(!n||!p){alert('Please enter your name and phone number.');return}
alert('Booking request submitted! We\'ll confirm availability within 24 hours. Thanks, '+n+'!');
}
let calMonth=new Date().getMonth(),calYear=new Date().getFullYear();
const MONTHS=['January','February','March','April','May','June','July','August','September','October','November','December'];
const BOOKED={dump:[[8,12],[15,18],[22,25]],flatbed:[[10,14]]}; 
function renderCal(){
document.getElementById('calTitle').textContent=MONTHS[calMonth]+' '+calYear;
const grid=document.getElementById('calGrid');
grid.innerHTML='';
['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].forEach(d=>{const h=document.createElement('div');h.className='cal-header';h.textContent=d;grid.appendChild(h)});
const first=new Date(calYear,calMonth,1).getDay();
const days=new Date(calYear,calMonth+1,0).getDate();
const today=new Date();
for(let i=0;i<first;i++){const e=document.createElement('div');e.className='cal-day empty';grid.appendChild(e)}
for(let d=1;d<=days;d++){
const el=document.createElement('div');
el.className='cal-day available';
el.textContent=d;
if(calYear===today.getFullYear()&&calMonth===today.getMonth()&&d===today.getDate())el.classList.add('today');
BOOKED.flatbed.forEach(r=>{if(d>=r[0]&&d<=r[1])el.classList.replace('available','rented')});
grid.appendChild(el);
}
}
function changeMonth(d){calMonth+=d;if(calMonth>11){calMonth=0;calYear++}if(calMonth<0){calMonth=11;calYear--}renderCal()}
renderCal();
document.querySelectorAll('.faq-q').forEach(q=>q.addEventListener('click',function(){this.parentElement.classList.toggle('open')}));
function toggleChat(){document.getElementById('chatWindow').classList.toggle('open')}
function sendChat(){
const input=document.getElementById('chatInput');
const msg=input.value.trim();
if(!msg)return;
const msgs=document.getElementById('chatMessages');
msgs.innerHTML+=`<div class="chat-msg user">${msg}</div>`;
input.value='';
msgs.scrollTop=msgs.scrollHeight;
setTimeout(()=>{
let reply="Thanks for reaching out! For availability, use the booking form above or call (701) 555-1234. What else can I help with?";
const lower=msg.toLowerCase();
if(lower.includes('dump'))reply="The PJ D7 Dump is $100/day, $1,400/week, $4,500/month. It's currently rented until Thursday. Want me to check later dates?";
else if(lower.includes('flatbed')||lower.includes('flat'))reply="The 24' Flatbed is $225/day. It's available now! Want to book it?";
else if(lower.includes('deliver'))reply="We deliver anywhere in the Williston Basin. Fee depends on distance — call (701) 555-1234 for a quote.";
else if(lower.includes('deposit'))reply="$50 deposit, collected at pickup. Returned same day on safe return. We photograph everything at pickup and return.";
else if(lower.includes('book')||lower.includes('rent'))reply="Great! Use the Book Online section above, or call/text (701) 555-1234. We confirm within 24 hours.";
msgs.innerHTML+=`<div class="chat-msg bot">${reply}</div>`;
msgs.scrollTop=msgs.scrollHeight;
},800);
}
function submitWaitlist(){
const n=document.getElementById('wlName').value;
const p=document.getElementById('wlPhone').value;
if(!n||!p){alert('Please enter your name and phone number.');return}
alert('Added to the waitlist, '+n+'. We\'ll text you when new trailers are available!');
document.getElementById('wlName').value='';
document.getElementById('wlPhone').value='';
}
window.addEventListener('scroll',()=>{
const btn=document.getElementById('backToTop');
if(window.pageYOffset>600)btn.classList.add('visible');
else btn.classList.remove('visible');
});
const si=document.querySelector('.scroll-indicator');
if(si){window.addEventListener('scroll',()=>{if(window.pageYOffset>200)si.style.opacity='0';else si.style.opacity='1'},{passive:true})}
function validateField(id,condition,msg){
const g=document.getElementById(id).closest('.form-group');
const em=g.querySelector('.error-msg');
if(!condition){
g.classList.add('error');g.classList.remove('valid');
if(!em){const e=document.createElement('div');e.className='error-msg';e.textContent=msg;g.appendChild(e)}
else{em.textContent=msg;em.style.display='block'}
return false;
}
g.classList.remove('error');g.classList.add('valid');
if(em)em.style.display='none';
return true;
}
function validateBooking(){
let ok=true;
ok&=validateField('bookName',document.getElementById('bookName').value.trim().length>0,'Name is required');
ok&=validateField('bookPhone',document.getElementById('bookPhone').value.trim().length>=7,'Valid phone number required');
ok&=validateField('bookEmail',!document.getElementById('bookEmail').value||document.getElementById('bookEmail').value.includes('@'),'Valid email required');
ok&=validateField('bookStart',document.getElementById('bookStart').value,'Pickup date required');
ok&=validateField('bookEnd',document.getElementById('bookEnd').value,'Return date required');
if(ok){
const s=new Date(document.getElementById('bookStart').value);
const e=new Date(document.getElementById('bookEnd').value);
if(e<=s){validateField('bookEnd',false,'Return must be after pickup');ok=false}
}
return ok;
}
const origSubmit=submitBooking;
submitBooking=function(){
if(!validateBooking())return;
const n=document.getElementById('bookName').value;
alert('Booking request submitted! We\'ll confirm availability within 24 hours. Thanks, '+n+'!');
};
['bookName','bookPhone','bookEmail','bookStart','bookEnd'].forEach(id=>{
const el=document.getElementById(id);
if(el)el.addEventListener('blur',()=>validateBooking());
});
const baSlider=document.getElementById('baSlider');
if(baSlider){
let dragging=false;
function moveSlider(x){
const r=baSlider.getBoundingClientRect();
let pct=((x-r.left)/r.width)*100;
pct=Math.max(5,Math.min(95,pct));
document.getElementById('baHandle').style.left=pct+'%';
baSlider.querySelector('.ba-after').style.clipPath='inset(0 0 0 '+pct+'%)';
}
baSlider.addEventListener('mousedown',e=>{dragging=true;moveSlider(e.clientX)});
document.addEventListener('mousemove',e=>{if(dragging)moveSlider(e.clientX)});
document.addEventListener('mouseup',()=>dragging=false);
baSlider.addEventListener('touchstart',e=>{dragging=true;moveSlider(e.touches[0].clientX)});
document.addEventListener('touchmove',e=>{if(dragging)moveSlider(e.touches[0].clientX)});
document.addEventListener('touchend',()=>dragging=false);
}
function copyLink(btn){
navigator.clipboard.writeText('https:
btn.classList.add('copied');
const orig=btn.textContent;
btn.textContent='✓ Copied!';
setTimeout(()=>{btn.classList.remove('copied');btn.textContent=orig},2000);
});
}
function shareSite(){
if(navigator.share){
navigator.share({title:'Regulator Logistics — Trailer Rentals',url:'https:
}
}
