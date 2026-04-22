# Shine

Shine Jewelry Store is a luxury e-commerce application for fine jewelry and precious gems, featuring an elegant marketplace interface where customers can browse and purchase exquisite rings, necklaces, bracelets, earrings, and luxury watches. Built on the Internet Computer Protocol (ICP), it provides a secure and decentralized shopping experience.

## Key Features

- **Secure Admin Authentication**: First registered user automatically becomes admin with full product and category management capabilities.
- **Product Management**:
  - Admins can add, edit, and delete jewelry items with name, description, price, category, and images.
  - Products are organized by jewelry categories (Rings, Necklaces, Bracelets, Earrings, Watches) for easy browsing.
  - Support for product images with drag-and-drop upload functionality (max 1MB).
  - Real-time form validation and error handling with success feedback.
  - Paginated product listings with table view showing images, categories, and prices formatted with commas.
- **Category Management**:
  - Admins can create and manage jewelry categories with descriptions and images.
  - Dynamic category filtering for enhanced user experience.
  - Visual category cards with custom images and drag-and-drop upload support.
  - Product count tracking per category with real-time updates.
  - Paginated category listings with delete functionality and confirmation dialogs.
- **Modern Marketplace UI**:
  - Hero section with rotating banner showcasing featured jewelry collections.
  - Responsive grid layout displaying jewelry with images, descriptions, and luxury pricing.
  - Category-based filtering system for different jewelry types.
  - Customer reviews and testimonials section focused on jewelry purchases.
- **Shopping Experience**:
  - Browse jewelry by category or view all products.
  - Detailed product cards with buy buttons linking to external payment systems.
  - Mobile-friendly responsive design with hamburger menu navigation.
  - Smooth scrolling and interactive elements optimized for luxury shopping experience.
- **Transaction Management**:
  - Automated transaction tracking via Stripe checkout session integration.
  - Real-time transaction status monitoring (checking, completed, failed).
  - User principal extraction from Stripe checkout sessions for decentralized user tracking.
  - Admin access to all transactions with comprehensive revenue analytics and user identification.
  - User-specific transaction history and order management dashboard.
  - Detailed line item viewing for completed transactions with modal interface.
  - Revenue calculation with total earnings and order completion metrics displayed in dashboard.
  - Transaction session ID management with truncated display for security and readability.
  - Status-based visual indicators with colored badges and icons for transaction states.
- **User Account System**:
  - Internet Identity authentication for secure, passwordless login.
  - Personal dashboard showing order history and transaction status.
  - Session ID copying functionality for easy reference and customer support.
  - Real-time order status updates (processing, completed, failed).
  - Protected user routes requiring authentication for purchases.
- **Admin Dashboard**:
  - Dedicated admin interface for product, category, and transaction management.
  - Revenue analytics with total earnings calculation and order completion tracking.
  - Comprehensive transaction monitoring with user principal identification.
  - Transaction details modal with line item viewing capability.
  - Secure admin authentication system with automatic first-user promotion.
  - Full CRUD operations for inventory management.
  - Multi-admin management system with add/remove functionality.
  - Settings configuration panel for Stripe API keys and proxy servers.
  - Test data loading capability for development and demonstration.
  - Tabbed interface with Products, Categories, Transactions, Settings, and Admins.
  - Pagination support for large datasets with configurable items per page.
  - Real-time success/error feedback with visual indicators.
  - Drag-and-drop image upload with file size validation (max 1MB).
- **Modern UI/UX**:
  - Clean, elegant design optimized for luxury jewelry branding.
  - Fully responsive layout working seamlessly on desktop and mobile.
  - Interactive hover effects and smooth transitions.
  - Integrated customer testimonials and feature highlights focused on jewelry excellence.

## Technical Specifications

### Backend Functions (Motoko)

#### Transaction Management

- `addTransaction(session_id: Text)`: Processes Stripe checkout sessions and extracts user principals
- `getTransactions()`: Admin-only function to retrieve all transactions with revenue data
- `getTransactionsByPrincipal()`: User-specific transaction history retrieval
- `getTransactionLineItems(session_id: Text, starting_after: ?Text)`: Fetches detailed line items from Stripe

#### Authentication & Authorization

- `initializeAuth()`: Sets first user as admin automatically
- `isAdmin(principal: Principal)`: Admin permission verification
- Internet Identity integration for decentralized authentication

#### Data Management

- `addProduct(...)`: Admin jewelry product creation with image upload and category assignment
- `addCategory(name: Text, description: Text, image: Text)`: Jewelry category management with image support
- `deleteProduct(id: Nat)`: Product removal functionality
- `deleteCategory(name: Text)`: Category deletion with validation
- `addAdmin(principal: Text)`: Multi-admin system for administrative access
- `removeAdmin(principal: Text)`: Admin removal functionality
- `getAdmins()`: Retrieve list of current administrators
- `setStripeApiKey(key: Text)`: Stripe API configuration
- `setProxy(url: ?Text)`: Proxy server configuration for HTTPS outcalls
- OrderedMap-based persistent storage for all entities

### Frontend Architecture (React + TypeScript)

#### Components

- **Marketplace**: Main jewelry store interface with category filtering and jewelry product browsing
- **UserAccount**: Personal dashboard with order history and transaction monitoring
- **Admin**: Comprehensive admin portal with five main sections:
  - Products management with pagination and CRUD operations
  - Categories management with image support and product counting
  - Transactions monitoring with revenue analytics and status tracking
  - Settings configuration for Stripe API keys and proxy servers
  - Admin management for adding/removing administrators
- **PaymentSuccess**: Post-purchase transaction processing and user feedback
- **TransactionDetailsModal**: Reusable modal for viewing detailed line items
- **Pagination**: Reusable pagination component for large datasets

#### State Management

- TanStack Query for API state management and caching
- React Query mutations for CRUD operations
- Real-time data invalidation and refetching

#### Key Features

- Internet Identity authentication integration
- Protected routes requiring login for purchases
- Client reference ID passing to Stripe for user tracking
- Responsive design with mobile-first approach

### API Integration

- **Stripe Checkout Sessions**: Automated transaction processing and user principal extraction
- **Stripe Line Items**: Detailed order information retrieval with pagination
- **HTTPS Outcalls**: Secure communication with Stripe API via idempotent proxy
