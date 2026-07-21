require('dotenv').config();
const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const { createClient } = require('@supabase/supabase-js');
const africastalking = require('africastalking');

const app = express();
const PORT = process.env.PORT || 3000;

// Initialize Supabase client with service key
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

// Initialize Africa's Talking
const at = africastalking({
  apiKey: process.env.AT_API_KEY,
  username: process.env.AT_USERNAME
});

const sms = at.SMS;

// Middleware
app.use(cors());
app.use(express.json());

// JWT Authentication Middleware
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }

  jwt.verify(token, process.env.JWT_SECRET, (err, decoded) => {
    if (err) {
      return res.status(403).json({ error: 'Invalid or expired token' });
    }
    req.user = decoded;
    next();
  });
};

// Helper function to send SMS to guardian
const sendGuardianSMS = async (guardianPhone, message) => {
  try {
    // Normalize phone number to E.164 format (+254XXXXXXXXX)
    let normalizedPhone = guardianPhone;
    if (!normalizedPhone.startsWith('+')) {
      if (normalizedPhone.startsWith('0')) {
        // Local format: 0769174601 -> +254769174601
        normalizedPhone = '+254' + normalizedPhone.substring(1);
      } else {
        // Already has country code but no +: 254769174601 -> +254769174601
        normalizedPhone = '+' + normalizedPhone;
      }
    }

    const options = {
      to: [normalizedPhone],
      message: message,
      from: 'BetStop' // You may need to register this sender ID
    };

    // Debug: log exact values being sent to AT
    console.log('SMS DEBUG - to value:', JSON.stringify(normalizedPhone));
    console.log('SMS DEBUG - to type:', Array.isArray([normalizedPhone]) ? 'array' : typeof [normalizedPhone]);
    console.log('SMS DEBUG - options.to:', JSON.stringify(options.to));

    // Use sandbox mode in development
    if (process.env.NODE_ENV === 'development') {
      console.log('[SMS Sandbox] Would send to:', guardianPhone, 'Message:', message);
      return { success: true, sandbox: true };
    }

    const response = await sms.send(options);
    return { success: true, response };
  } catch (error) {
    console.error('SMS sending failed:', error);
    return { success: false, error: error.message };
  }
};

// POST /api/auth/register
app.post('/api/auth/register', async (req, res) => {
  try {
    const { phone, name, guardian_name, guardian_phone, guardian_pin, cooling_hours, letter_to_self } = req.body;

    // Validate input
    if (!phone || !name || !guardian_name || !guardian_phone || !guardian_pin || !cooling_hours || !letter_to_self) {
      return res.status(400).json({ error: 'All fields are required' });
    }

    // Check if user already exists
    const { data: existingUser } = await supabase
      .from('users')
      .select('id')
      .eq('phone', phone)
      .single();

    if (existingUser) {
      return res.status(400).json({ error: 'User with this phone number already exists' });
    }

    // Hash the guardian PIN
    const pin_hash = await bcrypt.hash(guardian_pin, 10);

    // Create user
    const { data: user, error: userError } = await supabase
      .from('users')
      .insert({
        phone,
        name,
        streak_days: 0,
        total_saved_kes: 0
      })
      .select()
      .single();

    if (userError) throw userError;

    // Create guardian
    const { error: guardianError } = await supabase
      .from('guardians')
      .insert({
        user_id: user.id,
        name: guardian_name,
        phone: guardian_phone,
        pin_hash
      });

    if (guardianError) throw guardianError;

    // Create commitment with calculated end time
    const commitmentEnd = new Date(Date.now() + cooling_hours * 60 * 60 * 1000).toISOString();
    
    const { error: commitmentError } = await supabase
      .from('commitments')
      .insert({
        user_id: user.id,
        cooling_hours,
        commitment_end: commitmentEnd,
        letter_to_self,
        is_active: true
      });

    if (commitmentError) throw commitmentError;

    // Send SMS to guardian
    const guardianMessage = `${name} has enrolled in BetStop Kenya and chosen you as their accountability guardian. You will be notified if they attempt to gamble.`;
    await sendGuardianSMS(guardian_phone, guardianMessage);

    // Generate JWT token
    const token = jwt.sign(
      { user_id: user.id, phone: user.phone },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.status(201).json({
      user_id: user.id,
      token,
      user: { name: user.name, phone: user.phone }
    });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Registration failed', details: error.message });
  }
});

// POST /api/detections/sms
app.post('/api/detections/sms', authenticateToken, async (req, res) => {
  try {
    const { paybill, amount_kes, sms_text } = req.body;

    // Look up paybill
    const { data: paybillData, error: paybillError } = await supabase
      .from('paybills')
      .select('*')
      .eq('paybill', paybill)
      .eq('is_active', true)
      .single();

    if (paybillError || !paybillData) {
      return res.json({ detected: false, message: 'Paybill not found or inactive' });
    }

    // Get user and guardian info
    const { data: user, error: userError } = await supabase
      .from('users')
      .select('*, guardians(*)')
      .eq('id', req.user.user_id)
      .single();

    if (userError || !user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Insert detection record
    const { error: detectionError } = await supabase
      .from('detections')
      .insert({
        user_id: req.user.user_id,
        paybill,
        site_name: paybillData.site_name,
        amount_kes,
        source: 'sms',
        guardian_alerted: true
      });

    if (detectionError) throw detectionError;

    // Send SMS to guardian
    const time = new Date().toLocaleString();
    const guardianMessage = `⚠️ BetStop Alert: ${user.name} just sent KES ${amount_kes} to ${paybillData.site_name} at ${time}. Log in to BetStop to view details.`;
    await sendGuardianSMS(user.guardians.phone, guardianMessage);

    // Update user's total saved
    const { error: updateError } = await supabase
      .from('users')
      .update({
        total_saved_kes: user.total_saved_kes + parseFloat(amount_kes)
      })
      .eq('id', req.user.user_id);

    if (updateError) throw updateError;

    res.json({
      detected: true,
      site_name: paybillData.site_name,
      amount: amount_kes
    });
  } catch (error) {
    console.error('SMS detection error:', error);
    res.status(500).json({ error: 'Detection failed', details: error.message });
  }
});

// POST /api/detections/extension
app.post('/api/detections/extension', authenticateToken, async (req, res) => {
  try {
    const { domain, attempted_url } = req.body;

    // Look up domain
    const { data: domainData, error: domainError } = await supabase
      .from('blocked_domains')
      .select('*')
      .eq('domain', domain)
      .eq('is_active', true)
      .single();

    if (domainError || !domainData) {
      return res.json({ blocked: false, message: 'Domain not found or inactive' });
    }

    // Get user and guardian info
    const { data: user, error: userError } = await supabase
      .from('users')
      .select('*, guardians(*), commitments(*)')
      .eq('id', req.user.user_id)
      .single();

    if (userError || !user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Insert detection record
    const { error: detectionError } = await supabase
      .from('detections')
      .insert({
        user_id: req.user.user_id,
        site_name: domainData.site_name,
        source: 'extension',
        guardian_alerted: true
      });

    if (detectionError) throw detectionError;

    // Send SMS to guardian
    const guardianMessage = `⚠️ BetStop Alert: ${user.name} tried to access ${domainData.site_name} just now. Attempt was blocked.`;
    await sendGuardianSMS(user.guardians.phone, guardianMessage);

    // Get letter to self from commitment
    const letter_to_self = user.commitments?.letter_to_self || '';

    res.json({
      blocked: true,
      site_name: domainData.site_name,
      letter_to_self
    });
  } catch (error) {
    console.error('Extension detection error:', error);
    res.status(500).json({ error: 'Detection failed', details: error.message });
  }
});

// GET /api/user/dashboard
app.get('/api/user/dashboard', authenticateToken, async (req, res) => {
  try {
    // Get user data
    const { data: user, error: userError } = await supabase
      .from('users')
      .select('*')
      .eq('id', req.user.user_id)
      .single();

    if (userError || !user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Get commitment data
    const { data: commitment } = await supabase
      .from('commitments')
      .select('*')
      .eq('user_id', req.user.user_id)
      .eq('is_active', true)
      .single();

    // Get detections from this week
    const oneWeekAgo = new Date();
    oneWeekAgo.setDate(oneWeekAgo.getDate() - 7);

    const { count: detections_this_week } = await supabase
      .from('detections')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', req.user.user_id)
      .gte('detected_at', oneWeekAgo.toISOString());

    res.json({
      streak_days: user.streak_days,
      total_saved_kes: user.total_saved_kes,
      detections_this_week: detections_this_week || 0,
      commitment_ends_at: commitment?.commitment_end,
      letter_to_self: commitment?.letter_to_self
    });
  } catch (error) {
    console.error('Dashboard error:', error);
    res.status(500).json({ error: 'Failed to fetch dashboard', details: error.message });
  }
});

// GET /api/paybills
app.get('/api/paybills', async (req, res) => {
  try {
    const { data: paybills, error } = await supabase
      .from('paybills')
      .select('*')
      .eq('is_active', true);

    if (error) throw error;

    res.json(paybills);
  } catch (error) {
    console.error('Paybills fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch paybills' });
  }
});

// GET /api/domains
app.get('/api/domains', async (req, res) => {
  try {
    const { data: domains, error } = await supabase
      .from('blocked_domains')
      .select('*')
      .eq('is_active', true);

    if (error) throw error;

    res.json(domains);
  } catch (error) {
    console.error('Domains fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch domains' });
  }
});

// POST /api/guardian/disable
app.post('/api/guardian/disable', async (req, res) => {
  try {
    const { user_id, guardian_pin } = req.body;

    if (!user_id || !guardian_pin) {
      return res.status(400).json({ error: 'user_id and guardian_pin are required' });
    }

    // Get guardian with PIN hash
    const { data: guardian, error: guardianError } = await supabase
      .from('guardians')
      .select('*')
      .eq('user_id', user_id)
      .single();

    if (guardianError || !guardian) {
      return res.status(404).json({ error: 'Guardian not found' });
    }

    // Verify PIN
    const pinMatch = await bcrypt.compare(guardian_pin, guardian.pin_hash);

    if (!pinMatch) {
      return res.status(401).json({ error: 'Invalid PIN' });
    }

    // Deactivate commitment
    const { error: updateError } = await supabase
      .from('commitments')
      .update({ is_active: false })
      .eq('user_id', user_id)
      .eq('is_active', true);

    if (updateError) throw updateError;

    res.json({ success: true });
  } catch (error) {
    console.error('Disable monitoring error:', error);
    res.status(500).json({ error: 'Failed to disable monitoring', details: error.message });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Start server
app.listen(PORT, () => {
  console.log(`BetStop backend running on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});
